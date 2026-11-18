#!/usr/bin/env bash
# build.sh — PaddlePaddle GPU build for NVIDIA DGX Spark (GB10, aarch64, sm_121)
#
# Verified 2026-11-18 on DGX OS 7 (Ubuntu 24.04 arm64), CUDA 13.0, driver 580.x,
# Paddle v3.3.0 → paddlepaddle_gpu-3.3.0.dev20251226-cp312-cp312-linux_aarch64.whl
# (paddle.utils.run_check() green on GPU, PP-OCRv6 line OCR verified on real scans).
#
# Usage:
#   ./build.sh [PADDLE_TAG]     # default: v3.3.0
#   PADDLE_TAG=v3.3.1 ./build.sh
#
# Everything happens in $WORK_DIR (default: ./build-work, gitignored).
# Output wheel: $WORK_DIR/Paddle/build/python/dist/*.whl
#
# Known-good beyond upstream docs (PaddleOCR#17328, metaparadigma walkthrough):
#   1. libcudnn9-dev-cuda-13 + libnccl-dev (arm64, NVIDIA sbsa repo) must be
#      installed BEFORE cmake — upstream cmake assumes x86_64 paths otherwise.
#   2. pybind11-stubgen MUST be pinned <3: Paddle (as of v3.3.0) calls the 2.x
#      API run(..., sub_dir=...); pybind11-stubgen 3.0.0 changes the signature
#      and breaks the build at wheel-packing time (after ~1h of compiling).
#   3. Eigen-NEON workaround flags (from #17328) are mandatory on ARM.
#
# For tags >= v3.4.0: expect a FlashAttention compile segfault on GB10 (see
# Paddle issue #76215). Fix: comment out the flashattn block in
# cmake/third_party.cmake (patches/ may carry a .patch for this). Unverified.

set -euo pipefail

PADDLE_TAG="${1:-${PADDLE_TAG:-v3.3.0}}"
WORK_DIR="${WORK_DIR:-$(pwd)/build-work}"
JOBS="${JOBS:-6}"          # -j20 works on an idle box; 6 is safe next to vLLM
PY_BIN="${PY_BIN:-python3}" # 3.12 verified; cp313 is supported by Paddle 3.3

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

log "=== PaddlePaddle GPU build for DGX Spark (GB10) — tag: $PADDLE_TAG ==="

# ---- 1. system deps (idempotent) -------------------------------------------
log "system deps (sudo)"
sudo apt-get update -qq
sudo apt-get install -y \
    git cmake ninja-build swig gfortran patchelf \
    libopenblas-dev liblapack-dev \
    libssl-dev zlib1g-dev wget curl unzip \
    libcudnn9-dev-cuda-13 \
    libnccl-dev=2.32.6-1+cuda13.5 libnccl2=2.32.6-1+cuda13.5

# ---- 2. source --------------------------------------------------------------
log "clone Paddle $PADDLE_TAG (+ submodules) into $WORK_DIR/Paddle"
mkdir -p "$WORK_DIR"
if [ ! -d "$WORK_DIR/Paddle/.git" ]; then
    git -C "$WORK_DIR" clone --depth 1 --branch "$PADDLE_TAG" \
        https://github.com/PaddlePaddle/Paddle.git Paddle
fi
git -C "$WORK_DIR/Paddle" submodule update --init --recursive

# ---- 3. build venv (separate from any runtime venv!) ------------------------
log "build venv: $WORK_DIR/paddle-build"
[ -d "$WORK_DIR/paddle-build" ] || "$PY_BIN" -m venv "$WORK_DIR/paddle-build"
# shellcheck disable=SC1091
source "$WORK_DIR/paddle-build/bin/activate"
pip install --upgrade pip -q
pip install -q numpy protobuf cython wheel setuptools
pip install -q 'pybind11-stubgen==2.5.1'   # CRITICAL: 3.x breaks wheel packing
pip install -q -r "$WORK_DIR/Paddle/python/requirements.txt"

# ---- 4. patches (if any for this tag) ---------------------------------------
log "apply patches for $PADDLE_TAG (if present)"
for p in patches/"$PADDLE_TAG"/*.patch patches/common/*.patch; do
    [ -e "$p" ] || continue
    log "  applying $p"
    git -C "$WORK_DIR/Paddle" apply --check "$PWD/$p" \
        && git -C "$WORK_DIR/Paddle" apply "$PWD/$p" \
        || echo "  (skip $p — does not apply cleanly)" >&2
done

# ---- 5. cmake ---------------------------------------------------------------
log "cmake (Eigen-NEON workaround, sm_121, ARM flags from PaddleOCR#17328)"
mkdir -p "$WORK_DIR/Paddle/build"
cd "$WORK_DIR/Paddle/build"
cmake .. -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_GPU=ON \
    -DWITH_TESTING=OFF \
    -DCUDA_ARCH_NAME=Manual \
    -DCUDA_ARCH_BIN="12.1" \
    -DWITH_ARM=ON \
    -DWITH_AVX=OFF \
    -DWITH_MKL=OFF \
    -DWITH_MKLDNN=OFF \
    -DWITH_TENSORRT=OFF \
    -DPYTHON_EXECUTABLE="$(which python3)" \
    -DCMAKE_CUDA_FLAGS="-U__ARM_NEON -DEIGEN_DONT_VECTORIZE=1" \
    2>&1 | tee cmake_output.log | tail -5

# ---- 6. ninja ----------------------------------------------------------------
log "ninja -j$JOBS (expect ~1h at -j6, ~40min at -j20)"
ninja -j"$JOBS" 2>&1 | tee build_output.log | tail -5

# ---- 7. wheel ----------------------------------------------------------------
log "wheel:"
ls -lh python/dist/*.whl || { echo "✗ no wheel produced — check build_output.log" >&2; exit 1; }
sha256sum python/dist/*.whl | tee python/dist/*.whl.sha256

log "=== DONE ==="
log "smoke test in a SEPARATE venv (not the build venv):"
log "  python3 -m venv /tmp/paddle-test && source /tmp/paddle-test/bin/activate"
log "  pip install $(pwd)/python/dist/*.whl paddleocr"
log "  python -c 'import paddle; print(paddle.is_compiled_with_cuda()); paddle.utils.run_check()'"

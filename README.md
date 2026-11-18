# paddle-dgx

**PaddlePaddle GPU builds for the NVIDIA DGX Spark** (GB10 Grace Blackwell:
aarch64 + sm_121, CUDA 13) — a platform PaddlePaddle upstream does not ship
wheels for and has no plans to support ([Paddle#76215]). This repo carries the
verified build recipe, per-tag patches, and release wheels.

## Status

| Paddle tag | Wheel | Notes |
|---|---|---|
| v3.3.0 | [release](../../releases) `paddlepaddle_gpu-3.3.0.dev20251226-cp312-cp312-linux_aarch64.whl` | ✅ verified: `run_check()` green on GPU, PP-OCRv6 line OCR on real scans (German, umlauts correct) |
| v3.3.1 | [release](../../releases) `paddlepaddle_gpu-3.3.0.dev20260319-cp312-cp312-linux_aarch64.whl` | ✅ verified: `run_check()` green on GPU (built via `./build.sh v3.3.1`, unpatched) |
| v3.4.0 | — | ⚠️ expect FlashAttention compile segfault on GB10 (Paddle#76215); disable via `cmake/third_party.cmake` |

## Build

```bash
./build.sh              # v3.3.0 (verified)
./build.sh v3.3.1       # another tag
JOBS=20 ./build.sh      # full cores on an idle box
```

Requirements: DGX OS 7 (Ubuntu 24.04 arm64), CUDA 13 toolkit (`nvcc`),
driver 580.x, sudo. Everything else (cuDNN, NCCL, build deps) is installed
by the script.

## What this fixes beyond upstream docs

The upstream walkthroughs ([PaddleOCR#17328],
[metaparadigma]) get close but miss three things — all baked into `build.sh`:

1. **cuDNN + NCCL arm64 packages** must exist before cmake
   (`libcudnn9-dev-cuda-13`, `libnccl-dev` from the NVIDIA sbsa repo) —
   Paddle's cmake hardcodes x86_64 search paths otherwise.
2. **`pybind11-stubgen` pinned to 2.5.1** — Paddle (≤ v3.3.x) calls the 2.x
   API; 3.0.0 breaks the build at wheel-packing time, *after* the ~1h compile.
3. Eigen-NEON workaround flags (`-U__ARM_NEON -DEIGEN_DONT_VECTORIZE=1`)
   — from #17328, mandatory on ARM.

## Patches

`patches/<tag>/*.patch` and `patches/common/*.patch` are applied by
`build.sh` after submodule init. Currently empty — v3.3.0 builds unpatched.
First expected patch: FlashAttention disable for ≥ v3.4.0 (Paddle#76215).

## Install

Wheels are mirrored on the HF Hub for one-line installs:
<https://huggingface.co/skaledev/paddle-dgx>

```bash
# v3.3.1 (latest)
pip install https://huggingface.co/skaledev/paddle-dgx/resolve/main/paddlepaddle_gpu-3.3.0.dev20260319-cp312-cp312-linux_aarch64.whl
pip install paddleocr        # does NOT pull a CPU paddlepaddle
python -c "import paddle; print(paddle.is_compiled_with_cuda())"  # True
```

Python 3.12 (cp313 wheels would work too — Paddle 3.3 supports both).

## License

Wheels built from [PaddlePaddle/Paddle] (Apache-2.0). This repo's scripts:
Apache-2.0 as well.

[Paddle#76215]: https://github.com/PaddlePaddle/Paddle/issues/76215
[PaddleOCR#17328]: https://github.com/PaddlePaddle/PaddleOCR/discussions/17328
[metaparadigma]: https://news.metaparadigma.de/dgx-spark-installing-paddlepaddle-ocr-on-nvidia-dgx-spark-5348/
[PaddlePaddle/Paddle]: https://github.com/PaddlePaddle/Paddle

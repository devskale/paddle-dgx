# patches/

Applied by build.sh after `git submodule update`:
- `patches/<TAG>/*.patch` — tag-specific
- `patches/common/*.patch` — all tags

Currently empty: v3.3.0 builds unpatched.

## Expected first patch (≥ v3.4.0)

FlashAttention segfaults the compiler on GB10 (Paddle#76215). Fix: comment out
the flashattn block in `cmake/third_party.cmake`:

```cmake
# set(WITH_FLASHATTN_V3 ON)
# include(external/flashattn)
# list(APPEND third_Party_deps extern_flashattn)
```

Plus (per sarthaknimbalkar/dgx-spark-paddlepaddle-gpu, develop-branch era):
CUTLASS attention generators crash on sm_121 (`int("121(20)")`), warpctc/
warprnnt emit removed `compute_20`, SLEEF/tlfloat link error. None of these
applied to v3.3.0.

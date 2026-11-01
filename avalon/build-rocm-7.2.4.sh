#!/bin/bash
# Build Avalon's llama-server for gfx1100 against an unpacked ROCm 7.2.4.
# Set the paths below, or export them before running.
set -euo pipefail

ROCM=${ROCM:-$HOME/rocm-7.2.4}                  # unpacked ROCm 7.2.4 (has bin/, lib/, llvm/)
AVALON=${AVALON:-$HOME/src/Avalon}              # freriadoc/Avalon @ ad2c6e7
COMPAT=${COMPAT:-$ROCM/compat}                  # libxml2.so.2 + libicu74 from noble debs
NINJA=${NINJA:-$(command -v ninja || true)}

if [ -z "$NINJA" ]; then
  echo "ninja not found. Install it or export NINJA=/path/to/ninja" >&2
  exit 1
fi
if [ ! -d "$ROCM" ]; then
  echo "ROCm root not found: $ROCM" >&2
  exit 1
fi

export HIP_PLATFORM=amd
export ROCM_PATH="$ROCM"
export HIP_PATH="$ROCM"
export PATH="$ROCM/bin:$ROCM/llvm/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM/lib:$ROCM/llvm/lib:$COMPAT"

cd "$AVALON"
cmake -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1100 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ROCM/llvm/bin/amdclang" \
  -DCMAKE_CXX_COMPILER="$ROCM/llvm/bin/amdclang++" \
  -DCMAKE_HIP_COMPILER="$ROCM/llvm/bin/clang++" \
  -DCMAKE_HIP_COMPILER_ROCM_ROOT="$ROCM" -DCMAKE_PREFIX_PATH="$ROCM" \
  -DCMAKE_HIP_FLAGS="--rocm-path=$ROCM --rocm-device-lib-path=$ROCM/amdgcn/bitcode" \
  -DCMAKE_HIP_ARCHITECTURES=gfx1100
cmake --build build -j"$(nproc)" --target llama-server

echo BUILD-OK

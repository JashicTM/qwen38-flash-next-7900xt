#!/bin/bash
# Serve the Swift GSQ IQ3_S pack with Avalon's llama-server.
# Expects the repacked weights in MODEL_DIR and a build from build-rocm-7.2.4.sh.
set -euo pipefail

ROCM=${ROCM:-$HOME/rocm-7.2.4}
AVALON=${AVALON:-$HOME/src/Avalon}
COMPAT=${COMPAT:-$ROCM/compat}
MODEL_DIR=${MODEL_DIR:-$HOME/models/swift-gsq-iq3_s-avalon}
HOST=${HOST:-127.0.0.1}
PORT=${PORT:-8080}
GPU=${GPU:-0}

export LD_LIBRARY_PATH="$ROCM/lib:$ROCM/llvm/lib:$COMPAT"
export HIP_VISIBLE_DEVICES="$GPU"

cd "$MODEL_DIR"
exec "$AVALON/build/bin/llama-server" \
  -m Swift-Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf \
  -c 262144 -b 9536 -ub 9536 -fa on -ctk q8_0 -ctv q4_0 --jinja --parallel 1 \
  -md MTP/mtp-Qwen3.8-Flash-Next-shared-IQ3K-IQ4NL-FR65k.gguf --spec-type draft-mtp \
  --spec-draft-n-max 2 -ubd 256 -ctkd q8_0 -ctvd q8_0 \
  --alias swift-qwen3.8-flash-next-gsq-iq3_s \
  --host "$HOST" --port "$PORT" "$@"

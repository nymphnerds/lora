#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

[[ -x "${LORA_BIN_DIR}/ztrain-stop-official-ui" ]] && "${LORA_BIN_DIR}/ztrain-stop-official-ui" || true
[[ -x "${LORA_BIN_DIR}/ztrain-stop-gradio-ui" ]] && "${LORA_BIN_DIR}/ztrain-stop-gradio-ui" || true
[[ -x "${LORA_BIN_DIR}/ztrain-stop-queue-worker" ]] && "${LORA_BIN_DIR}/ztrain-stop-queue-worker" || true

echo "LoRA trainer services stopped."

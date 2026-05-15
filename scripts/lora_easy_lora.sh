#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -f "${LORA_INSTALL_ROOT}/ui/manager.html" ]]; then
  echo "Easy LoRA UI is missing. Run Update or Repair for the LoRA module." >&2
  exit 1
fi

if [[ ! -x "${LORA_BIN_DIR}/ztrain-start-official-ui" || ! -x "${LORA_BIN_DIR}/ztrain-start-queue-worker" ]]; then
  echo "LoRA trainer is not installed. Run Install or Repair for the LoRA module first." >&2
  exit 1
fi

"${LORA_BIN_DIR}/ztrain-start-queue-worker"
"${LORA_BIN_DIR}/ztrain-start-official-ui"

echo "Easy LoRA UI is installed at ${LORA_INSTALL_ROOT}/ui/manager.html"
echo "AI Toolkit backend is ready on http://127.0.0.1:${LORA_UI_PORT}"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -x "${LORA_BIN_DIR}/ztrain-start-official-ui" ]]; then
  echo "LoRA trainer is not installed. Run scripts/install_lora.sh first." >&2
  exit 1
fi

"${LORA_BIN_DIR}/ztrain-start-queue-worker"
"${LORA_BIN_DIR}/ztrain-start-official-ui"

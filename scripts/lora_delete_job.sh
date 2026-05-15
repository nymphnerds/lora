#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -x "${LORA_VENV_DIR}/bin/python" ]]; then
  echo "LoRA trainer Python is missing at ${LORA_VENV_DIR}/bin/python. Repair LoRA first." >&2
  exit 1
fi

"${LORA_VENV_DIR}/bin/python" "${SCRIPT_DIR}/lora_job_control.py" delete \
  --datasets-root "${LORA_DATASET_DIR}" \
  --loras-root "${LORA_OUTPUT_DIR}" \
  --jobs-root "${LORA_JOB_DIR}" \
  --start-ui "${LORA_BIN_DIR}/ztrain-start-official-ui" \
  --start-worker "${LORA_BIN_DIR}/ztrain-start-queue-worker" \
  "$@"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

python3 "${SCRIPT_DIR}/lora_job_control.py" status \
  --datasets-root "${LORA_DATASET_DIR}" \
  --loras-root "${LORA_OUTPUT_DIR}" \
  --jobs-root "${LORA_JOB_DIR}" \
  --start-ui "${LORA_BIN_DIR}/ztrain-start-official-ui" \
  --start-worker "${LORA_BIN_DIR}/ztrain-start-queue-worker" \
  "$@"

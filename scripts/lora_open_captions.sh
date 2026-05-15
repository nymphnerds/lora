#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

python3 "${SCRIPT_DIR}/lora_dataset.py" captions \
  --datasets-root "${LORA_DATASET_DIR}" \
  "$@"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -f "${LORA_INSTALL_ROOT}/ui/manager.html" ]]; then
  echo "Easy LoRA UI is missing. Run Update or Repair for the LoRA module." >&2
  exit 1
fi

echo "Easy LoRA UI is installed at ${LORA_INSTALL_ROOT}/ui/manager.html"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

echo "install_root=${LORA_INSTALL_ROOT}"

for log_file in \
  "${LORA_LOG_DIR}/aitk-ui.log" \
  "${LORA_LOG_DIR}/aitk-worker.log" \
  "${LORA_LOG_DIR}/aitk-gradio.log"; do
  if [[ -f "${log_file}" ]]; then
    echo
    echo "==> ${log_file}"
    tail -n "${LORA_LOG_LINES:-140}" "${log_file}"
  fi
done

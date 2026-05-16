#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

echo "install_root=${LORA_INSTALL_ROOT}"

mkdir -p "${LORA_LOG_DIR}"
last_log="${LORA_LOG_DIR}/aitk-ui.log"
for candidate in \
  "${LORA_LOG_DIR}/aitk-ui.log" \
  "${LORA_LOG_DIR}/aitk-worker.log" \
  "${LORA_LOG_DIR}/aitk-gradio.log"; do
  if [[ -f "${candidate}" ]]; then
    last_log="${candidate}"
    break
  fi
done
touch "${last_log}"
echo "logs_dir=${LORA_LOG_DIR}"
echo "last_log=${last_log}"

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

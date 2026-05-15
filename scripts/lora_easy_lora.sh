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

ui_running=false
worker_running=false
lora_port_open "${LORA_UI_PORT}" >/dev/null 2>&1 && ui_running=true
lora_queue_worker_running && worker_running=true

if [[ "${worker_running}" == "false" ]]; then
  "${LORA_BIN_DIR}/ztrain-start-queue-worker"
else
  echo "AI Toolkit queue worker already running."
fi

if [[ "${ui_running}" == "false" ]]; then
  "${LORA_BIN_DIR}/ztrain-start-official-ui"
else
  echo "AI Toolkit UI already running on http://127.0.0.1:${LORA_UI_PORT}"
fi

echo "Easy LoRA UI is installed at ${LORA_INSTALL_ROOT}/ui/manager.html"
echo "AI Toolkit backend is ready on http://127.0.0.1:${LORA_UI_PORT}"

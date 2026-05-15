#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

[[ -x "${LORA_BIN_DIR}/ztrain-stop-official-ui" ]] && "${LORA_BIN_DIR}/ztrain-stop-official-ui" || true
[[ -x "${LORA_BIN_DIR}/ztrain-stop-gradio-ui" ]] && "${LORA_BIN_DIR}/ztrain-stop-gradio-ui" || true
[[ -x "${LORA_BIN_DIR}/ztrain-stop-queue-worker" ]] && "${LORA_BIN_DIR}/ztrain-stop-queue-worker" || true

pkill -u "$(id -u)" -f "concurrently.*dist/cron/worker.js.*next start --port ${LORA_UI_PORT}" || true
pkill -u "$(id -u)" -f "concurrently.*next start --port ${LORA_UI_PORT}" || true
pkill -u "$(id -u)" -f "next start --port ${LORA_UI_PORT}" || true
pkill -u "$(id -u)" -f "node_modules/.bin/next start --port ${LORA_UI_PORT}" || true
pkill -u "$(id -u)" -f "(^|/)node dist/cron/worker.js($| )" || true

echo "LoRA trainer services stopped."

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

kill_lora_matches() {
  local pattern="$1"
  local signal="${2:-TERM}"
  local pid

  while read -r pid; do
    [[ -n "${pid}" ]] || continue
    [[ "${pid}" == "$$" || "${pid}" == "${PPID}" ]] && continue
    kill "-${signal}" "${pid}" >/dev/null 2>&1 || true
  done < <(pgrep -u "$(id -u)" -f "${pattern}" 2>/dev/null || true)
}

kill_lora_matches "concurrently.*dist/cron/worker[.]js.*next start --port ${LORA_UI_PORT}"
kill_lora_matches "concurrently.*next start --port ${LORA_UI_PORT}"
kill_lora_matches "next start --port ${LORA_UI_PORT}"
kill_lora_matches "node_modules/.bin/next start --port ${LORA_UI_PORT}"
kill_lora_matches "next-server"
kill_lora_matches "(^|/)node dist/cron/worker[.]js($| )"
kill_lora_matches "server_port=${LORA_GRADIO_PORT}.*flux_train_ui|flux_train_ui[.]py"

for _ in {1..20}; do
  if ! lora_port_open "${LORA_UI_PORT}" >/dev/null 2>&1 &&
     ! lora_port_open "${LORA_GRADIO_PORT}" >/dev/null 2>&1 &&
     ! pgrep -u "$(id -u)" -f "concurrently.*next start --port ${LORA_UI_PORT}" >/dev/null 2>&1 &&
     ! pgrep -u "$(id -u)" -f "(^|/)node dist/cron/worker[.]js($| )" >/dev/null 2>&1; then
    echo "LoRA trainer services stopped."
    exit 0
  fi
  sleep 0.25
done

kill_lora_matches "concurrently.*dist/cron/worker[.]js.*next start --port ${LORA_UI_PORT}" KILL
kill_lora_matches "concurrently.*next start --port ${LORA_UI_PORT}" KILL
kill_lora_matches "next start --port ${LORA_UI_PORT}" KILL
kill_lora_matches "node_modules/.bin/next start --port ${LORA_UI_PORT}" KILL
kill_lora_matches "next-server" KILL
kill_lora_matches "(^|/)node dist/cron/worker[.]js($| )" KILL
kill_lora_matches "server_port=${LORA_GRADIO_PORT}.*flux_train_ui|flux_train_ui[.]py" KILL

echo "LoRA trainer services stopped."

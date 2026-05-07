#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

installed=false
repo_ready=false
venv_ready=false
node_ready=false
ui_ready=false
adapter_ready=false
model_ready=false
official_ui_running=false
gradio_running=false
worker_running=false
detail="Not installed."

if [[ -x "${LORA_BIN_DIR}/ztrain-start-official-ui" ]]; then
  installed=true
  detail="LoRA trainer installed."
fi

[[ -d "${LORA_REPO_DIR}/.git" ]] && repo_ready=true
[[ -x "${LORA_VENV_DIR}/bin/python" ]] && venv_ready=true
[[ -x "${LORA_NODE_DIR}/bin/node" ]] && node_ready=true
[[ -d "${LORA_UI_DIR}/.next" ]] && ui_ready=true
[[ -f "${LORA_ADAPTER_DIR}/selected_adapter_path.txt" ]] && adapter_ready=true
[[ -d "${LORA_MODEL_DIR}/transformer" && -d "${LORA_MODEL_DIR}/text_encoder" && -d "${LORA_MODEL_DIR}/tokenizer" ]] && model_ready=true

if lora_port_open "${LORA_UI_PORT}" >/dev/null 2>&1; then
  official_ui_running=true
fi

if lora_port_open "${LORA_GRADIO_PORT}" >/dev/null 2>&1; then
  gradio_running=true
fi

if pgrep -u "$(id -u)" -f "dist/cron/worker.js" >/dev/null 2>&1; then
  worker_running=true
fi

cat <<EOF
id=lora
name=LoRA
installed=${installed}
repo_ready=${repo_ready}
venv_ready=${venv_ready}
node_ready=${node_ready}
ui_ready=${ui_ready}
adapter_ready=${adapter_ready}
model_ready=${model_ready}
official_ui_running=${official_ui_running}
gradio_running=${gradio_running}
worker_running=${worker_running}
official_ui_url=http://127.0.0.1:${LORA_UI_PORT}
gradio_url=http://127.0.0.1:${LORA_GRADIO_PORT}
install_root=${LORA_INSTALL_ROOT}
datasets=${LORA_DATASET_DIR}
loras=${LORA_OUTPUT_DIR}
jobs=${LORA_JOB_DIR}
detail=${detail}
EOF

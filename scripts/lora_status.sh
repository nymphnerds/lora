#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

installed=false
runtime_present=false
data_present=false
user_data_present=false
training_assets_present=false
repo_ready=false
venv_ready=false
node_ready=false
ui_ready=false
adapter_ready=false
model_ready=false
assets_ready=false
official_ui_running=false
gradio_running=false
worker_running=false
lora_count=0
dataset_count=0
job_count=0
version=not-installed
health=missing
state=available
marker="${LORA_INSTALL_ROOT}/.nymph-module-version"
detail="Not installed."

if [[ -f "${marker}" ]]; then
  installed=true
  runtime_present=true
  version="$(head -n 1 "${marker}" 2>/dev/null || true)"
  [[ -n "${version}" ]] || version=unknown
  detail="LoRA trainer installed."
fi

if [[ -d "${LORA_OUTPUT_DIR}" ]]; then
  lora_count="$(find "${LORA_OUTPUT_DIR}" -type f -name '*.safetensors' 2>/dev/null | wc -l | tr -d '[:space:]')"
fi

if [[ -d "${LORA_DATASET_DIR}" ]]; then
  dataset_count="$(find "${LORA_DATASET_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d '[:space:]')"
fi

if [[ -d "${LORA_JOB_DIR}" ]]; then
  job_count="$(find "${LORA_JOB_DIR}" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) 2>/dev/null | wc -l | tr -d '[:space:]')"
fi

if [[ "${dataset_count}" != "0" || "${lora_count}" != "0" || "${job_count}" != "0" ]] ||
   [[ -d "${LORA_CONFIG_DIR}" && -n "$(find "${LORA_CONFIG_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]] ||
   [[ -d "${LORA_LOG_DIR}" && -n "$(find "${LORA_LOG_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
  user_data_present=true
fi

if [[ -d "${LORA_MODEL_DIR}" && -n "$(find "${LORA_MODEL_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]] ||
   [[ -d "${LORA_ADAPTER_DIR}" && -n "$(find "${LORA_ADAPTER_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
  training_assets_present=true
fi

if [[ "${user_data_present}" == "true" || "${training_assets_present}" == "true" ]]; then
  data_present=true
fi

if [[ "${installed}" == "true" ]]; then
  [[ -d "${LORA_REPO_DIR}/.git" ]] && repo_ready=true
  [[ -x "${LORA_VENV_DIR}/bin/python" ]] && venv_ready=true
  [[ -x "${LORA_NODE_DIR}/bin/node" ]] && node_ready=true
  [[ -d "${LORA_UI_DIR}/.next" ]] && ui_ready=true
  [[ -f "${LORA_ADAPTER_DIR}/selected_adapter_path.txt" ]] && adapter_ready=true
  [[ -d "${LORA_MODEL_DIR}/transformer" && -d "${LORA_MODEL_DIR}/text_encoder" && -d "${LORA_MODEL_DIR}/tokenizer" && -f "${LORA_MODEL_DIR}/vae/diffusion_pytorch_model.safetensors" ]] && model_ready=true
  [[ "${adapter_ready}" == "true" && "${model_ready}" == "true" ]] && assets_ready=true
fi

if [[ "${installed}" == "true" ]] && lora_port_open "${LORA_UI_PORT}" >/dev/null 2>&1; then
  official_ui_running=true
fi

if [[ "${installed}" == "true" ]] && lora_port_open "${LORA_GRADIO_PORT}" >/dev/null 2>&1; then
  gradio_running=true
fi

if [[ "${installed}" == "true" ]] && pgrep -u "$(id -u)" -f "dist/cron/worker.js" >/dev/null 2>&1; then
  worker_running=true
fi

if [[ "${official_ui_running}" == "true" || "${gradio_running}" == "true" || "${worker_running}" == "true" ]]; then
  state=running
  health=ok
elif [[ "${installed}" == "true" && "${repo_ready}" == "true" && "${venv_ready}" == "true" && "${node_ready}" == "true" && "${ui_ready}" == "true" && "${assets_ready}" == "true" ]]; then
  state=installed
  health=ok
elif [[ "${installed}" == "true" && "${repo_ready}" == "true" && "${venv_ready}" == "true" && "${node_ready}" == "true" && "${ui_ready}" == "true" ]]; then
  state=needs_assets
  health=ok
  detail="LoRA runtime is installed. Training assets are not ready yet."
elif [[ "${installed}" == "true" ]]; then
  state=needs_attention
  health=degraded
  detail="LoRA trainer is installed, but one or more runtime pieces need attention."
elif [[ "${data_present}" == "true" ]]; then
  detail="LoRA preserved data remains, but runtime files are not installed."
fi

cat <<EOF
id=lora
name=LoRA
installed=${installed}
runtime_present=${runtime_present}
data_present=${data_present}
user_data_present=${user_data_present}
training_assets_present=${training_assets_present}
version=${version}
repo_ready=${repo_ready}
venv_ready=${venv_ready}
node_ready=${node_ready}
ui_ready=${ui_ready}
adapter_ready=${adapter_ready}
model_ready=${model_ready}
assets_ready=${assets_ready}
official_ui_running=${official_ui_running}
gradio_running=${gradio_running}
worker_running=${worker_running}
queue_worker_running=${worker_running}
queue_running=${worker_running}
active_state=idle
active_info=No active training job detected.
lora_count=${lora_count}
dataset_count=${dataset_count}
job_count=${job_count}
running=$([[ "${state}" == "running" ]] && echo true || echo false)
state=${state}
health=${health}
official_ui_url=http://127.0.0.1:${LORA_UI_PORT}
gradio_url=http://127.0.0.1:${LORA_GRADIO_PORT}
install_root=${LORA_INSTALL_ROOT}
datasets=${LORA_DATASET_DIR}
loras=${LORA_OUTPUT_DIR}
jobs=${LORA_JOB_DIR}
logs_dir=${LORA_LOG_DIR}
marker=${marker}
detail=${detail}
EOF

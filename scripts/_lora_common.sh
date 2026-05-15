#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LORA_INSTALL_ROOT="${LORA_INSTALL_ROOT:-${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}}"
LORA_REPO_DIR="${ZIMAGE_TRAINER_REPO_DIR:-$LORA_INSTALL_ROOT/ai-toolkit}"
LORA_VENV_DIR="${ZIMAGE_TRAINER_VENV:-$LORA_REPO_DIR/venv}"
LORA_BIN_DIR="${LORA_INSTALL_ROOT}/bin"
LORA_LOG_DIR="${LORA_INSTALL_ROOT}/logs"
LORA_DATASET_DIR="${ZIMAGE_DATASET_ROOT:-$LORA_INSTALL_ROOT/datasets}"
LORA_OUTPUT_DIR="${ZIMAGE_LORA_ROOT:-$LORA_INSTALL_ROOT/loras}"
LORA_JOB_DIR="${LORA_INSTALL_ROOT}/jobs"
LORA_CONFIG_DIR="${LORA_INSTALL_ROOT}/config"
LORA_ADAPTER_DIR="${LORA_INSTALL_ROOT}/adapters/zimage_turbo_training_adapter"
LORA_MODEL_DIR="${LORA_INSTALL_ROOT}/models/Tongyi-MAI/Z-Image-Turbo"
LORA_ASSET_READY_MARKER="${LORA_INSTALL_ROOT}/.training-assets-ready"
LORA_NODE_DIR="${LORA_INSTALL_ROOT}/.node20"
LORA_UI_DIR="${LORA_REPO_DIR}/ui"
LORA_UI_PORT="${ZIMAGE_TRAINER_UI_PORT:-8675}"
LORA_GRADIO_PORT="${ZIMAGE_TRAINER_GRADIO_PORT:-7861}"

lora_port_open() {
  local port="$1"
  python3 - "${port}" <<'PY'
import socket
import sys

s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
else:
    raise SystemExit(0)
finally:
    s.close()
PY
}

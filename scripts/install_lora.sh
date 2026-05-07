#!/usr/bin/env bash
set -euo pipefail

TRAINER_ROOT="${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}"
REPO_DIR="${ZIMAGE_TRAINER_REPO_DIR:-$TRAINER_ROOT/ai-toolkit}"
VENV_DIR="${ZIMAGE_TRAINER_VENV:-$REPO_DIR/venv}"
DATASET_ROOT="${ZIMAGE_DATASET_ROOT:-$TRAINER_ROOT/datasets}"
LORA_ROOT="${ZIMAGE_LORA_ROOT:-$TRAINER_ROOT/loras}"
LOG_ROOT="$TRAINER_ROOT/logs"
JOB_ROOT="$TRAINER_ROOT/jobs"
CONFIG_ROOT="$TRAINER_ROOT/config"
BIN_ROOT="$TRAINER_ROOT/bin"
MODEL_ROOT="$TRAINER_ROOT/models/Tongyi-MAI/Z-Image-Turbo"
ADAPTER_ROOT="$TRAINER_ROOT/adapters/zimage_turbo_training_adapter"
ADAPTER_PATH_FILE="$ADAPTER_ROOT/selected_adapter_path.txt"
UI_DIR="$REPO_DIR/ui"
NODE_ROOT="$TRAINER_ROOT/.node20"
NODE_BIN_DIR="$NODE_ROOT/bin"
UI_DB_PATH="$REPO_DIR/aitk_db.db"
UI_PORT="${ZIMAGE_TRAINER_UI_PORT:-8675}"
GRADIO_PORT="${ZIMAGE_TRAINER_GRADIO_PORT:-7861}"

echo "Z-Image Trainer: preparing isolated AI Toolkit sidecar."
mkdir -p "$TRAINER_ROOT" "$DATASET_ROOT" "$LORA_ROOT" "$LOG_ROOT" "$JOB_ROOT" "$CONFIG_ROOT" "$BIN_ROOT" "$MODEL_ROOT" "$ADAPTER_ROOT"

echo "Stopping any running trainer UIs before repair..."
pkill -u "$(id -u)" -f "next start --port ${UI_PORT}|dist/cron/worker.js" || true
pkill -u "$(id -u)" -f "ui/node_modules/.bin/concurrently.*next start --port ${UI_PORT}" || true
pkill -u "$(id -u)" -f "server_port=${GRADIO_PORT}.*flux_train_ui|flux_train_ui.py" || true

if ! command -v git >/dev/null 2>&1; then
  echo "Installing git..."
  sudo apt-get update
  sudo apt-get install -y git
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Installing Python..."
  sudo apt-get update
  sudo apt-get install -y python3 python3-venv python3-pip
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Installing curl..."
  sudo apt-get update
  sudo apt-get install -y curl
fi

if ! command -v xz >/dev/null 2>&1; then
  echo "Installing xz-utils..."
  sudo apt-get update
  sudo apt-get install -y xz-utils
fi

if [[ -d "$REPO_DIR/.git" ]]; then
  echo "AI Toolkit repo found. Updating..."
  git -C "$REPO_DIR" pull --ff-only
  git -C "$REPO_DIR" submodule update --init --recursive
else
  echo "Cloning AI Toolkit into $REPO_DIR..."
  git clone https://github.com/ostris/ai-toolkit.git "$REPO_DIR"
  git -C "$REPO_DIR" submodule update --init --recursive
fi

echo "Restoring the official AI Toolkit Prisma schema database path..."
UI_DIR="$UI_DIR" python3 - <<'PYEOF'
import os
from pathlib import Path

path = Path(os.environ["UI_DIR"]) / "prisma" / "schema.prisma"
text = path.read_text(encoding="utf-8")
updated = text.replace('url      = env("DATABASE_URL")', 'url      = "file:../../aitk_db.db"')
if updated != text:
    path.write_text(updated, encoding="utf-8")
PYEOF

echo "Applying Gradio 6 compatibility patch to flux_train_ui.py..."
REPO_DIR="$REPO_DIR" python3 - <<'PYEOF'
import os
import re
from pathlib import Path

path = Path(os.environ["REPO_DIR"]) / "flux_train_ui.py"
text = path.read_text(encoding="utf-8")
updated = text
updated = updated.replace(",\n                                    show_share_button=False", "")
updated = updated.replace(",\n                                    show_download_button=False", "")
updated = updated.replace("with gr.Blocks(theme=theme, css=css) as demo:", "with gr.Blocks() as demo:")
updated = updated.replace("with gr.Blocks(theme=theme) as demo:", "with gr.Blocks() as demo:")
updated = updated.replace("with gr.Blocks(css=css) as demo:", "with gr.Blocks() as demo:")
updated = re.sub(
    r"demo\.launch\((.*?)\)",
    lambda match: "demo.launch(theme=theme, css=css, share=False, show_error=True)"
    if "theme=theme" not in match.group(1) and "css=css" not in match.group(1)
    else f"demo.launch({match.group(1)})",
    updated,
    count=1,
    flags=re.DOTALL,
)
if updated != text:
    path.write_text(updated, encoding="utf-8")
PYEOF

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Creating official AI Toolkit venv at $VENV_DIR..."
  python3 -m venv "$VENV_DIR"
fi

echo "Installing AI Toolkit Python dependencies..."
"$VENV_DIR/bin/python" -m pip install --upgrade pip wheel setuptools
"$VENV_DIR/bin/python" -m pip install --no-cache-dir torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 --index-url https://download.pytorch.org/whl/cu128
"$VENV_DIR/bin/python" -m pip install -r "$REPO_DIR/requirements.txt"
"$VENV_DIR/bin/python" -m pip install --upgrade accelerate transformers diffusers huggingface_hub Pillow

echo "Installing local Node.js runtime for the official AI Toolkit UI..."
mkdir -p "$NODE_ROOT"
if [[ ! -x "$NODE_BIN_DIR/node" ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  node_archive="$(curl -fsSL https://nodejs.org/dist/latest-v20.x/SHASUMS256.txt | awk '/linux-x64\.tar\.xz$/ {print $2; exit}')"
  if [[ -z "$node_archive" ]]; then
    echo "Failed to resolve latest Node.js v20 Linux archive." >&2
    exit 1
  fi
  curl -fsSL -o "$temp_dir/node.tar.xz" "https://nodejs.org/dist/latest-v20.x/${node_archive}"
  rm -rf "$NODE_ROOT"/*
  tar -xJf "$temp_dir/node.tar.xz" -C "$NODE_ROOT" --strip-components=1
  rm -rf "$temp_dir"
  trap - EXIT
fi
export PATH="$NODE_BIN_DIR:$PATH"
echo "Node runtime: $("${NODE_BIN_DIR}/node" -v)"

echo "Prefetching Z-Image Turbo training model bundle..."
MODEL_ROOT="$MODEL_ROOT" "$VENV_DIR/bin/python" - <<'PYEOF'
import os
from pathlib import Path

from huggingface_hub import snapshot_download

model_root = Path(os.environ["MODEL_ROOT"])
model_root.mkdir(parents=True, exist_ok=True)

snapshot_download(
    repo_id="Tongyi-MAI/Z-Image-Turbo",
    local_dir=str(model_root),
    allow_patterns=[
        "transformer/*",
        "text_encoder/*",
        "vae/*",
        "tokenizer/*",
        "*.json",
        "*.txt",
        "*.model",
    ],
)

required_paths = [
    model_root / "transformer",
    model_root / "text_encoder",
    model_root / "vae" / "diffusion_pytorch_model.safetensors",
    model_root / "tokenizer",
]
missing = [str(path) for path in required_paths if not path.exists()]
if missing:
    raise SystemExit(
        "Trainer model prefetch for Tongyi-MAI/Z-Image-Turbo is incomplete. Missing: "
        + ", ".join(missing)
    )

print(f"Z-Image Turbo trainer model bundle ready: {model_root}", flush=True)
PYEOF

echo "Prefetching Turbo training adapter..."
ADAPTER_ROOT="$ADAPTER_ROOT" ADAPTER_PATH_FILE="$ADAPTER_PATH_FILE" "$VENV_DIR/bin/python" - <<'PYEOF'
import os
from pathlib import Path

from huggingface_hub import snapshot_download

adapter_dir = Path(os.environ["ADAPTER_ROOT"])
path_file = Path(os.environ["ADAPTER_PATH_FILE"])
adapter_dir.mkdir(parents=True, exist_ok=True)

snapshot_download(
    repo_id="ostris/zimage_turbo_training_adapter",
    local_dir=str(adapter_dir),
    allow_patterns=["*.safetensors", "*.bin", "*.pt", "*.pth", "*.ckpt"],
)

candidates = sorted(
    [
        path for path in adapter_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in {".safetensors", ".bin", ".pt", ".pth", ".ckpt"}
    ],
    key=lambda path: (
        0 if "_v1" in path.name.lower() else 1,
        0 if path.suffix.lower() == ".safetensors" else 1,
        0 if path.parent == adapter_dir else 1,
        len(path.name),
        str(path).lower(),
    ),
)

if not candidates:
    raise SystemExit("No adapter weight file was downloaded for ostris/zimage_turbo_training_adapter")

selected = candidates[0].resolve()
path_file.write_text(str(selected) + "\n", encoding="utf-8")
print(f"Turbo training adapter ready: {selected}", flush=True)
PYEOF

echo "Installing official AI Toolkit UI dependencies..."
(
  cd "$UI_DIR"
  npm install
  npx prisma generate
)

echo "Applying Prisma schema to AI Toolkit UI database..."
mkdir -p "$(dirname "$UI_DB_PATH")"
rm -f "$UI_DB_PATH"
(
  cd "$UI_DIR"
  npx prisma db push --schema prisma/schema.prisma
)
echo "AI Toolkit UI database ready: $UI_DB_PATH"

echo "Building official AI Toolkit UI..."
(
  cd "$UI_DIR"
  npm run build
)

cat > "$CONFIG_ROOT/zimage-ai-toolkit.template.yaml" <<'EOF'
---
job: extension
config:
  name: "my_first_zimage_lora"
  process:
    - type: 'sd_trainer'
      training_folder: "/home/nymph/ZImage-Trainer/loras"
      device: cuda:0
      network:
        type: "lora"
        linear: 32
        linear_alpha: 32
      save:
        dtype: "fp16"
        save_every: 250
        max_step_saves_to_keep: 4
      datasets:
        - folder_path: "/home/nymph/ZImage-Trainer/datasets/my_first_zimage_lora"
          caption_ext: "txt"
          caption_dropout_rate: 0.05
          cache_latents_to_disk: false
          resolution: [ 1024 ]
      train:
        batch_size: 1
        steps: 3000
        gradient_accumulation: 1
        train_unet: true
        train_text_encoder: false
        gradient_checkpointing: true
        noise_scheduler: "flowmatch"
        timestep_type: "weighted"
        content_or_style: "balanced"
        optimizer: "adamw8bit"
        optimizer_params:
          weight_decay: 0.0001
        unload_text_encoder: false
        cache_text_embeddings: false
        lr: 0.0001
        ema_config:
          use_ema: false
          ema_decay: 0.99
        skip_first_sample: true
        force_first_sample: false
        disable_sampling: false
        dtype: "fp16"
        diff_output_preservation: false
        diff_output_preservation_multiplier: 1
        diff_output_preservation_class: "person"
        switch_boundary_every: 1
        loss_type: "mse"
      model:
        name_or_path: "/home/nymph/ZImage-Trainer/models/Tongyi-MAI/Z-Image-Turbo"
        quantize: false
        qtype: "qfloat8"
        quantize_te: false
        qtype_te: "qfloat8"
        arch: "zimage:turbo"
        low_vram: false
        model_kwargs: {}
        layer_offloading: false
        layer_offloading_text_encoder_percent: 1
        layer_offloading_transformer_percent: 1
        assistant_lora_path: "/home/nymph/ZImage-Trainer/adapters/zimage_turbo_training_adapter/zimage_turbo_training_adapter_v1.safetensors"
      sample:
        sampler: "flowmatch"
        sample_every: 250
        width: 1024
        height: 1024
        samples:
          - prompt: "mountain lake landscape"
        neg: ""
        seed: 42
        walk_seed: true
        guidance_scale: 1
        sample_steps: 8
        num_frames: 1
        fps: 1
meta:
  name: "[name]"
  version: '1.0'
EOF

cat > "$BIN_ROOT/ztrain-run-config" <<'RUNCFG_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: ztrain-run-config /path/to/config.yaml" >&2
  exit 2
fi

CONFIG_PATH="$1"
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Training config not found: $CONFIG_PATH" >&2
  exit 1
fi

if [[ -z "${HOME:-}" || ! -d "${HOME}" || "${HOME}" == "/root" ]]; then
  DETECTED_HOME="$(getent passwd "$(id -un)" | cut -d: -f6 || true)"
  if [[ -n "${DETECTED_HOME}" && -d "${DETECTED_HOME}" ]]; then
    export HOME="${DETECTED_HOME}"
  fi
fi

export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-${USER}}"

TRAINER_ROOT="${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}"
LOG_ROOT="${ZIMAGE_TRAINER_LOG_ROOT:-$TRAINER_ROOT/logs}"
RUN_STATE_DIR="${ZIMAGE_TRAINER_RUN_STATE_DIR:-$TRAINER_ROOT/run}"
PID_FILE="$RUN_STATE_DIR/active_train.pid"
mkdir -p "$LOG_ROOT" "$RUN_STATE_DIR"

cd "$TRAINER_ROOT/ai-toolkit"
source "$TRAINER_ROOT/ai-toolkit/venv/bin/activate"

readarray -t TRAIN_INFO < <(python3 - <<'PYINFO' "$CONFIG_PATH"
from pathlib import Path
import sys
import yaml

config_path = Path(sys.argv[1])
data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
config = data.get("config", {})
processes = config.get("process", []) or []
proc = processes[0] if processes else {}
name = str(config.get("name") or "training").strip()
steps = int(proc.get("train", {}).get("steps", 0) or 0)
training_folder = str(proc.get("training_folder") or "").strip()
db_path = ""
if training_folder and name:
    db_path = f"{training_folder.rstrip('/')}/{name}/loss_log.db"
print(name)
print(steps)
print(db_path)
PYINFO
)

RUN_NAME="${TRAIN_INFO[0]:-training}"
TOTAL_STEPS="${TRAIN_INFO[1]:-0}"
PROGRESS_DB="${TRAIN_INFO[2]:-}"
RUN_JOB_ID="${AITK_JOB_ID:-}"
LOG_FILE="$LOG_ROOT/${RUN_NAME}-$(date +%Y%m%d-%H%M%S).log"

cleanup() {
  rm -f "$PID_FILE"
}

trap cleanup EXIT

if [[ "$TOTAL_STEPS" =~ ^[0-9]+$ && "$TOTAL_STEPS" -gt 0 ]]; then
  echo "TRAIN_PROGRESS current=0 total=$TOTAL_STEPS"
fi

python run.py "$CONFIG_PATH" > >(tee "$LOG_FILE") 2>&1 &
TRAIN_PID=$!

PROGRESS_PID=""
if [[ -n "$PROGRESS_DB" && "$TOTAL_STEPS" =~ ^[0-9]+$ && "$TOTAL_STEPS" -gt 0 ]]; then
  python3 -u - <<'PYPROG' "$PROGRESS_DB" "$TOTAL_STEPS" "$TRAIN_PID" &
import os
import sqlite3
import sys
import time
from pathlib import Path

db_path = Path(sys.argv[1])
total = int(sys.argv[2])
pid = int(sys.argv[3])
last = -1

def alive(process_id: int) -> bool:
    try:
        os.kill(process_id, 0)
        return True
    except OSError:
        return False

def read_current() -> int | None:
    if not db_path.exists():
        return None
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1.0)
        try:
            row = con.execute("SELECT MAX(step) FROM steps").fetchone()
        finally:
            con.close()
        if not row or row[0] is None:
            return None
        return min(int(row[0]) + 1, total)
    except Exception:
        return None

while alive(pid):
    current = read_current()
    if current is not None and current != last:
        print(f"TRAIN_PROGRESS current={current} total={total}", flush=True)
        last = current
    time.sleep(1.0)

current = read_current()
if current is not None and current != last:
    print(f"TRAIN_PROGRESS current={current} total={total}", flush=True)
PYPROG
  PROGRESS_PID=$!
fi

cat > "$PID_FILE" <<EOF
SHELL_PID=$$
TRAIN_PID=$TRAIN_PID
PROGRESS_PID=${PROGRESS_PID:-}
CONFIG_PATH=$CONFIG_PATH
RUN_NAME=$RUN_NAME
AITK_JOB_ID=${RUN_JOB_ID:-}
LOG_FILE=$LOG_FILE
EOF

set +e
wait "$TRAIN_PID"
TRAIN_EXIT=$?
set -e

if [[ -n "$PROGRESS_PID" ]]; then
  wait "$PROGRESS_PID" || true
fi

if [[ "$TRAIN_EXIT" -eq 0 && "$TOTAL_STEPS" =~ ^[0-9]+$ && "$TOTAL_STEPS" -gt 0 ]]; then
  echo "TRAIN_PROGRESS current=$TOTAL_STEPS total=$TOTAL_STEPS"
fi

exit "$TRAIN_EXIT"
RUNCFG_EOF

chmod +x "$BIN_ROOT/ztrain-run-config"

cat > "$BIN_ROOT/ztrain-start-queue-worker" <<'QUEUE_WORKER_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HOME:-}" || ! -d "${HOME}" || "${HOME}" == "/root" ]]; then
  DETECTED_HOME="$(getent passwd "$(id -un)" | cut -d: -f6 || true)"
  if [[ -n "${DETECTED_HOME}" && -d "${DETECTED_HOME}" ]]; then
    export HOME="${DETECTED_HOME}"
  fi
fi

TRAINER_ROOT="${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}"
UI_DIR="${ZIMAGE_TRAINER_REPO_DIR:-$TRAINER_ROOT/ai-toolkit}/ui"
NODE_BIN_DIR="$TRAINER_ROOT/.node20/bin"
WORKER_LOG="$TRAINER_ROOT/logs/aitk-worker.log"
mkdir -p "$(dirname "$WORKER_LOG")"
export PATH="$TRAINER_ROOT/ai-toolkit/venv/bin:$NODE_BIN_DIR:$UI_DIR/node_modules/.bin:$PATH"

if pgrep -u "$(id -u)" -f "dist/cron/worker.js" >/dev/null 2>&1; then
  echo "AI Toolkit queue worker already running."
  exit 0
fi

cd "$UI_DIR"
nohup "$NODE_BIN_DIR/node" dist/cron/worker.js > "$WORKER_LOG" 2>&1 &
WORKER_PID=$!
for _ in {1..20}; do
  if ! kill -0 "$WORKER_PID" >/dev/null 2>&1; then
    echo "AI Toolkit queue worker exited before it finished booting." >&2
    exit 1
  fi
  sleep 0.25
done

echo "AI Toolkit queue worker started."
QUEUE_WORKER_EOF

cat > "$BIN_ROOT/ztrain-stop-queue-worker" <<'QUEUE_WORKER_STOP_EOF'
#!/usr/bin/env bash
set -euo pipefail

pkill -u "$(id -u)" -f "dist/cron/worker.js" || true
echo "AI Toolkit queue worker stopped."
QUEUE_WORKER_STOP_EOF

cat > "$BIN_ROOT/ztrain-start-official-ui" <<'OFFICIAL_UI_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HOME:-}" || ! -d "${HOME}" || "${HOME}" == "/root" ]]; then
  DETECTED_HOME="$(getent passwd "$(id -un)" | cut -d: -f6 || true)"
  if [[ -n "${DETECTED_HOME}" && -d "${DETECTED_HOME}" ]]; then
    export HOME="${DETECTED_HOME}"
  fi
fi

TRAINER_ROOT="${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}"
UI_DIR="${ZIMAGE_TRAINER_REPO_DIR:-$TRAINER_ROOT/ai-toolkit}/ui"
NODE_BIN_DIR="$TRAINER_ROOT/.node20/bin"
UI_PORT="${ZIMAGE_TRAINER_UI_PORT:-8675}"
UI_LOG="$TRAINER_ROOT/logs/aitk-ui.log"
mkdir -p "$(dirname "$UI_LOG")"
export PATH="$TRAINER_ROOT/ai-toolkit/venv/bin:$NODE_BIN_DIR:$UI_DIR/node_modules/.bin:$PATH"

if ss -ltn 2>/dev/null | grep -q ":${UI_PORT} "; then
  echo "AI Toolkit UI already running on port $UI_PORT."
  exit 0
fi

cd "$UI_DIR"
if [[ ! -d ".next" ]]; then
  echo "AI Toolkit UI build is missing. Run Repair Trainer first." >&2
  exit 1
fi
nohup npm run start > "$UI_LOG" 2>&1 &
UI_PID=$!

for _ in {1..40}; do
  if python3 - <<PYEOF >/dev/null 2>&1
import socket
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int("$UI_PORT")))
    raise SystemExit(0)
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PYEOF
  then
    echo "AI Toolkit UI started on http://localhost:$UI_PORT"
    exit 0
  fi

  if ! kill -0 "$UI_PID" >/dev/null 2>&1; then
    echo "Official AI Toolkit UI process exited before localhost:$UI_PORT became reachable." >&2
    exit 1
  fi

  sleep 0.5
done

echo "Official AI Toolkit UI did not become reachable on localhost:$UI_PORT." >&2
exit 1
OFFICIAL_UI_EOF

cat > "$BIN_ROOT/ztrain-stop-official-ui" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

UI_PORT="${ZIMAGE_TRAINER_UI_PORT:-8675}"
pkill -u "$(id -u)" -f "next start --port ${UI_PORT}" || true
pkill -u "$(id -u)" -f "node_modules/.bin/next start --port ${UI_PORT}" || true
pkill -u "$(id -u)" -f "ui/node_modules/.bin/concurrently.*next start --port ${UI_PORT}" || true
pkill -u "$(id -u)" -f "next-server" || true
pkill -u "$(id -u)" -f "dist/cron/worker.js" || true
for _ in {1..40}; do
  if ! ss -ltn 2>/dev/null | grep -q ":${UI_PORT} "; then
    echo "AI Toolkit UI stopped."
    exit 0
  fi
  sleep 0.25
done
echo "AI Toolkit UI did not stop cleanly." >&2
exit 1
EOF

chmod +x "$BIN_ROOT/ztrain-start-queue-worker" "$BIN_ROOT/ztrain-stop-queue-worker" "$BIN_ROOT/ztrain-start-official-ui" "$BIN_ROOT/ztrain-stop-official-ui"

cat > "$BIN_ROOT/ztrain-start-gradio-ui" <<'GRADIO_UI_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HOME:-}" || ! -d "${HOME}" || "${HOME}" == "/root" ]]; then
  DETECTED_HOME="$(getent passwd "$(id -un)" | cut -d: -f6 || true)"
  if [[ -n "${DETECTED_HOME}" && -d "${DETECTED_HOME}" ]]; then
    export HOME="${DETECTED_HOME}"
  fi
fi

TRAINER_ROOT="${ZIMAGE_TRAINER_ROOT:-$HOME/ZImage-Trainer}"
REPO_DIR="${ZIMAGE_TRAINER_REPO_DIR:-$TRAINER_ROOT/ai-toolkit}"
VENV_DIR="${ZIMAGE_TRAINER_VENV:-$REPO_DIR/venv}"
GRADIO_PORT="${ZIMAGE_TRAINER_GRADIO_PORT:-7861}"
GRADIO_LOG="$TRAINER_ROOT/logs/aitk-gradio.log"
mkdir -p "$(dirname "$GRADIO_LOG")"

if python - <<PYEOF >/dev/null 2>&1
import socket
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int("$GRADIO_PORT")))
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
finally:
    s.close()
PYEOF
then
  echo "AI Toolkit Gradio UI already running on port $GRADIO_PORT."
  exit 0
fi

cd "$REPO_DIR"
source "$VENV_DIR/bin/activate"
export REPO_DIR
nohup python - <<PYEOF > "$GRADIO_LOG" 2>&1 &
import os
import sys
import traceback

repo_dir = os.environ["REPO_DIR"] if "REPO_DIR" in os.environ else "$REPO_DIR"
sys.path.insert(0, repo_dir)
os.chdir(repo_dir)

try:
    import flux_train_ui as flux_ui

    flux_ui.demo.launch(
        theme=getattr(flux_ui, "theme", None),
        css=getattr(flux_ui, "css", None),
        server_name="127.0.0.1",
        server_port=int(os.environ.get("ZIMAGE_TRAINER_GRADIO_PORT", "$GRADIO_PORT")),
        share=False,
        show_error=True,
        inbrowser=False,
    )
except Exception:
    traceback.print_exc()
    raise
PYEOF
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if python - <<PYEOF >/dev/null 2>&1
import socket
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int("$GRADIO_PORT")))
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
finally:
    s.close()
PYEOF
  then
    echo "AI Toolkit Gradio UI started on http://localhost:$GRADIO_PORT"
    exit 0
  fi
  sleep 1
done
echo "AI Toolkit Gradio UI failed to stay running. Check $GRADIO_LOG" >&2
exit 1
GRADIO_UI_EOF

cat > "$BIN_ROOT/ztrain-stop-gradio-ui" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

GRADIO_PORT="${ZIMAGE_TRAINER_GRADIO_PORT:-7861}"
pkill -u "$(id -u)" -f "server_port=${GRADIO_PORT}.*flux_train_ui|flux_train_ui.py" || true
echo "AI Toolkit Gradio UI stopped."
EOF

chmod +x "$BIN_ROOT/ztrain-start-gradio-ui" "$BIN_ROOT/ztrain-stop-gradio-ui"

echo "Z-Image Trainer installed."
echo "Trainer root: $TRAINER_ROOT"
echo "Datasets: $DATASET_ROOT"
echo "LoRA outputs: $LORA_ROOT"
echo "AI Toolkit repo: $REPO_DIR"
echo "AI Toolkit venv: $VENV_DIR"
echo "AI Toolkit UI: $UI_DIR"
echo "AI Toolkit UI Node runtime: $NODE_ROOT"
echo "AI Toolkit UI database: $UI_DB_PATH"
echo "AI Toolkit Gradio UI port: $GRADIO_PORT"
echo "Trainer model cache: $MODEL_ROOT"
echo "Default method: Z-Image Turbo LoRA training with AI Toolkit and ostris/zimage_turbo_training_adapter."
echo "Official UI launch: $BIN_ROOT/ztrain-start-official-ui"
echo "Gradio UI launch: $BIN_ROOT/ztrain-start-gradio-ui"

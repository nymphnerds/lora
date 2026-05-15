#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -x "${LORA_VENV_DIR}/bin/python" ]]; then
  echo "LoRA runtime is not installed yet. Install LoRA before preparing training assets." >&2
  exit 1
fi

mkdir -p "${LORA_MODEL_DIR}" "${LORA_ADAPTER_DIR}"
export HF_HUB_DISABLE_PROGRESS_BARS=1

echo "Preparing LoRA training assets."
echo "This downloads the Z-Image Turbo training model bundle and assistant training adapter."
echo "Existing partial Hugging Face downloads will be resumed when possible."
echo "Model cache: ${LORA_MODEL_DIR}"
echo "Adapter cache: ${LORA_ADAPTER_DIR}"
echo "FETCH_ASSETS_PROGRESS status=starting phase=metadata model_cache=${LORA_MODEL_DIR} adapter_cache=${LORA_ADAPTER_DIR}"

MODEL_ROOT="${LORA_MODEL_DIR}" \
ADAPTER_ROOT="${LORA_ADAPTER_DIR}" \
ADAPTER_PATH_FILE="${LORA_ADAPTER_DIR}/selected_adapter_path.txt" \
"${LORA_VENV_DIR}/bin/python" - <<'PYEOF'
import fnmatch
import os
import threading
import time
from pathlib import Path

from huggingface_hub import HfApi, hf_hub_download


class Asset:
    def __init__(self, filename: str, size: int) -> None:
        self.filename = filename
        self.size = size


def format_bytes(value: int) -> str:
    size = float(max(value, 0))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{value} B"


def format_duration(seconds: float) -> str:
    total = max(int(seconds), 0)
    minutes, secs = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def local_summary(root: Path) -> tuple[int, int]:
    count = 0
    total = 0
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        count += 1
        try:
            total += path.stat().st_size
        except OSError:
            pass
    return count, total


def repo_assets(repo_id: str, patterns: list[str]) -> list[Asset]:
    try:
        info = HfApi().model_info(repo_id, files_metadata=True)
    except Exception as exc:
        raise SystemExit(f"Hugging Face metadata check failed for {repo_id}: {exc}") from exc

    selected = [
        Asset(sibling.rfilename, int(getattr(sibling, "size", 0) or 0))
        for sibling in (info.siblings or [])
        if any(fnmatch.fnmatch(sibling.rfilename, pattern) for pattern in patterns)
    ]
    selected.sort(key=lambda asset: asset.filename.lower())
    total = sum(asset.size for asset in selected)
    print(
        f"Hugging Face plan: {repo_id} -> {len(selected)} files, about {format_bytes(total)}.",
        flush=True,
    )
    for index, asset in enumerate(selected, start=1):
        print(
            f"  plan {index:02d}/{len(selected):02d}: {asset.filename} ({format_bytes(asset.size)})",
            flush=True,
        )
    return selected


def start_monitor(root: Path, label: str, item_label: str) -> tuple[threading.Event, threading.Thread]:
    stop = threading.Event()
    started = time.monotonic()

    def monitor() -> None:
        while not stop.wait(10):
            count, total = local_summary(root)
            print(
                f"{label} still working on {item_label}: elapsed={format_duration(time.monotonic() - started)} local_files={count} local_size={format_bytes(total)}",
                flush=True,
            )

    thread = threading.Thread(target=monitor, daemon=True)
    thread.start()
    return stop, thread


def download_assets(repo_id: str, root: Path, assets: list[Asset], label: str) -> None:
    started = time.monotonic()
    before_count, before_size = local_summary(root)
    print(
        f"{label} local cache before download: {before_count} files, {format_bytes(before_size)} at {root}",
        flush=True,
    )

    for index, asset in enumerate(assets, start=1):
        target = root / asset.filename
        if target.exists() and (asset.size <= 0 or target.stat().st_size == asset.size):
            print(
                f"{label} asset {index}/{len(assets)} already present: {asset.filename} ({format_bytes(target.stat().st_size)})",
                flush=True,
            )
            continue

        item_started = time.monotonic()
        print(
            f"{label} asset {index}/{len(assets)} downloading: {asset.filename} ({format_bytes(asset.size)})",
            flush=True,
        )
        stop, thread = start_monitor(root, label, f"{index}/{len(assets)} {asset.filename}")
        try:
            hf_hub_download(
                repo_id=repo_id,
                filename=asset.filename,
                local_dir=str(root),
                force_download=False,
            )
        finally:
            stop.set()
            thread.join(timeout=1)

        actual_size = target.stat().st_size if target.exists() else 0
        print(
            f"{label} asset {index}/{len(assets)} done: {asset.filename} ({format_bytes(actual_size)}) in {format_duration(time.monotonic() - item_started)}",
            flush=True,
        )

    after_count, after_size = local_summary(root)
    print(
        f"{label} complete in {format_duration(time.monotonic() - started)}: local_files={after_count} local_size={format_bytes(after_size)}",
        flush=True,
    )


model_root = Path(os.environ["MODEL_ROOT"])
adapter_root = Path(os.environ["ADAPTER_ROOT"])
adapter_path_file = Path(os.environ["ADAPTER_PATH_FILE"])
model_root.mkdir(parents=True, exist_ok=True)
adapter_root.mkdir(parents=True, exist_ok=True)

print("FETCH_ASSETS_PROGRESS status=running phase=metadata waiting_on=Hugging Face file lists", flush=True)

model_assets = repo_assets(
    "Tongyi-MAI/Z-Image-Turbo",
    [
        "transformer/*",
        "text_encoder/*",
        "vae/*",
        "tokenizer/*",
        "*.json",
        "*.txt",
        "*.model",
    ],
)
print(
    "FETCH_ASSETS_PROGRESS status=running phase=model_bundle waiting_on=Z-Image Turbo model downloads",
    flush=True,
)
download_assets("Tongyi-MAI/Z-Image-Turbo", model_root, model_assets, "Z-Image Turbo model bundle")

required_model_paths = [
    model_root / "transformer",
    model_root / "text_encoder",
    model_root / "vae" / "diffusion_pytorch_model.safetensors",
    model_root / "tokenizer",
]
missing_model_paths = [str(path) for path in required_model_paths if not path.exists()]
if missing_model_paths:
    raise SystemExit(
        "Trainer model asset fetch is incomplete. Missing: " + ", ".join(missing_model_paths)
    )

adapter_assets = repo_assets(
    "ostris/zimage_turbo_training_adapter",
    ["*.safetensors", "*.bin", "*.pt", "*.pth", "*.ckpt"],
)
print(
    "FETCH_ASSETS_PROGRESS status=running phase=training_adapter waiting_on=adapter weight downloads",
    flush=True,
)
download_assets(
    "ostris/zimage_turbo_training_adapter",
    adapter_root,
    adapter_assets,
    "Turbo training adapter",
)

adapter_candidates = sorted(
    [
        path for path in adapter_root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".safetensors", ".bin", ".pt", ".pth", ".ckpt"}
    ],
    key=lambda path: (
        0 if "_v1" in path.name.lower() else 1,
        0 if path.suffix.lower() == ".safetensors" else 1,
        0 if path.parent == adapter_root else 1,
        len(path.name),
        str(path).lower(),
    ),
)
if not adapter_candidates:
    raise SystemExit("No adapter weight file was downloaded for ostris/zimage_turbo_training_adapter")

selected_adapter = adapter_candidates[0].resolve()
adapter_path_file.write_text(str(selected_adapter) + "\n", encoding="utf-8")
print(f"Turbo training adapter selected: {selected_adapter}", flush=True)
print("FETCH_ASSETS_PROGRESS status=complete phase=ready", flush=True)
print("LoRA training assets ready.", flush=True)
PYEOF

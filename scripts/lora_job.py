#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import math
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

from lora_dataset import prepare_metadata


AITK_BASE_URL = "http://127.0.0.1:8675"


@dataclass(frozen=True)
class Preset:
    id: str
    label: str
    type_label: str
    amount_label: str
    steps: int
    save_every: int
    max_step_saves_to_keep: int
    sample_every: int
    disable_sampling: bool
    cache_text_embeddings: bool
    learning_rate: str
    rank: int
    resolution: int
    content_or_style: str
    low_vram: bool
    guidance_scale: int
    sample_steps: int
    sample_prompt: str


def resolve_preset(preset_id: str) -> Preset:
    normalized = (preset_id or "").strip().lower()
    if normalized == "fast_test":
        return Preset("fast_test", "Fast Test", "Turbo", "Quick Check", 500, 0, 0, 0, True, True, "1e-4", 8, 512, "balanced", False, 1, 8, "")
    if normalized in {"strong_style", "style_high_noise"}:
        return Preset("strong_style", "Strong Style", "Style", "High Noise", 5000, 1250, 4, 250, False, True, "1e-4", 16, 1024, "content", False, 1, 8, "")
    if normalized in {"style", "style_balanced", "style_light"}:
        return Preset("style", "Style", "Style", "Balanced", 3000, 750, 4, 250, False, True, "1e-4", 16, 1024, "balanced", False, 1, 8, "")
    return Preset("baseline", "Baseline", "Turbo", "Baseline", 3000, 750, 4, 250, False, True, "1e-4", 16, 1024, "balanced", False, 1, 8, "")


def compute_save_every(steps: int, checkpoint_count: int) -> int:
    if steps <= 0 or checkpoint_count <= 0:
        return 0
    return max(1, steps // checkpoint_count)


def normalize_sample_prompt(prompt: str | None) -> str:
    if not prompt or not prompt.strip():
        return ""
    trimmed = prompt.strip()
    if (trimmed.startswith("'") and trimmed.endswith("'")) or (
        trimmed.startswith('"') and trimmed.endswith('"')
    ):
        trimmed = trimmed[1:-1]
    return trimmed.replace("''", "'").strip()


def decode_sample_prompt(value: str | None) -> str:
    if not value:
        return ""
    try:
        return base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")
    except Exception:
        return value


def apply_overrides(
    preset: Preset,
    *,
    steps: int | None,
    learning_rate: str | None,
    rank: int | None,
    low_vram: bool | None,
    sample_prompt: str | None,
    checkpoint_count: int | None,
) -> Preset:
    resolved_steps = steps if steps and steps > 0 else preset.steps
    resolved_rank = rank if rank and rank > 0 else preset.rank
    resolved_learning_rate = learning_rate.strip() if learning_rate and learning_rate.strip() else preset.learning_rate
    resolved_low_vram = preset.low_vram if low_vram is None else low_vram
    resolved_sample_prompt = normalize_sample_prompt(sample_prompt) or preset.sample_prompt
    resolved_checkpoint_count = checkpoint_count if checkpoint_count is not None and checkpoint_count >= 0 else preset.max_step_saves_to_keep
    return replace(
        preset,
        steps=resolved_steps,
        learning_rate=resolved_learning_rate,
        rank=resolved_rank,
        low_vram=resolved_low_vram,
        sample_prompt=resolved_sample_prompt,
        save_every=compute_save_every(resolved_steps, resolved_checkpoint_count),
        max_step_saves_to_keep=resolved_checkpoint_count,
    )


def parse_learning_rate(value: str) -> float:
    try:
        parsed = float(value.strip())
    except Exception:
        return 1e-4
    return parsed if parsed > 0 and math.isfinite(parsed) else 1e-4


def yaml_quote(value: str) -> str:
    return "'" + value.replace("\r", " ").replace("\n", " ").replace("'", "''") + "'"


def bool_text(value: bool) -> str:
    return "true" if value else "false"


def adapter_candidates(adapter_dir: Path, adapter_version: str) -> list[Path]:
    marker = f"_{adapter_version}"
    candidates = [
        path
        for path in adapter_dir.rglob("*")
        if path.is_file()
        and path.suffix.lower() in {".safetensors", ".bin", ".pt", ".pth", ".ckpt"}
        and marker in path.name.lower()
    ]
    return sorted(
        candidates,
        key=lambda path: (
            0 if path.suffix.lower() == ".safetensors" else 1,
            0 if path.parent == adapter_dir else 1,
            len(path.name),
            str(path).lower(),
        ),
    )


def ensure_adapter(adapter_dir: Path, adapter_version: str) -> Path:
    normalized_version = "v2" if adapter_version.lower() == "v2" else "v1"
    adapter_dir.mkdir(parents=True, exist_ok=True)

    path_files = [adapter_dir / f"selected_adapter_path_{normalized_version}.txt"]
    if normalized_version == "v1":
        path_files.append(adapter_dir / "selected_adapter_path.txt")

    for path_file in path_files:
        if not path_file.is_file():
            continue
        selected = Path(path_file.read_text(encoding="utf-8").strip())
        if selected.is_file():
            return selected.resolve()

    candidates = adapter_candidates(adapter_dir, normalized_version)
    if not candidates:
        raise SystemExit(
            f"No Turbo training adapter {normalized_version} weight was found under {adapter_dir}. "
            "Run Fetch Training Assets first."
        )

    selected = candidates[0].resolve()
    (adapter_dir / f"selected_adapter_path_{normalized_version}.txt").write_text(str(selected) + "\n", encoding="utf-8")
    if normalized_version == "v1":
        (adapter_dir / "selected_adapter_path.txt").write_text(str(selected) + "\n", encoding="utf-8")
    return selected


def ensure_model_assets(model_dir: Path) -> None:
    required_paths = [
        model_dir / "model_index.json",
        model_dir / "transformer" / "diffusion_pytorch_model-00001-of-00003.safetensors",
        model_dir / "transformer" / "diffusion_pytorch_model-00002-of-00003.safetensors",
        model_dir / "transformer" / "diffusion_pytorch_model-00003-of-00003.safetensors",
        model_dir / "transformer" / "diffusion_pytorch_model.safetensors.index.json",
        model_dir / "text_encoder" / "model-00001-of-00003.safetensors",
        model_dir / "text_encoder" / "model-00002-of-00003.safetensors",
        model_dir / "text_encoder" / "model-00003-of-00003.safetensors",
        model_dir / "text_encoder" / "model.safetensors.index.json",
        model_dir / "vae" / "diffusion_pytorch_model.safetensors",
        model_dir / "tokenizer" / "merges.txt",
    ]
    missing = [path for path in required_paths if not path.is_file() or path.stat().st_size <= 0]
    if missing:
        raise SystemExit(
            "Z-Image Turbo training model assets are incomplete. Run Fetch Training Assets first. "
            f"Missing: {missing[0]}"
        )


def build_config_yaml(
    *,
    name: str,
    dataset_path: Path,
    lora_root: Path,
    db_path: Path,
    model_dir: Path,
    adapter_path: Path,
    preset: Preset,
) -> str:
    return f"""---
# nymphs_preset_id: {preset.id}
job: extension
config:
  name: {yaml_quote(name)}
  process:
    - type: 'sd_trainer'
      training_folder: {yaml_quote(str(lora_root))}
      sqlite_db_path: {yaml_quote(str(db_path))}
      device: cuda:0
      network:
        type: "lora"
        linear: {preset.rank}
        linear_alpha: {preset.rank}
      save:
        dtype: "bf16"
        save_every: {preset.save_every}
        max_step_saves_to_keep: {preset.max_step_saves_to_keep}
      logging:
        log_every: 1
        use_ui_logger: true
      datasets:
        - folder_path: {yaml_quote(str(dataset_path))}
          caption_ext: "txt"
          caption_dropout_rate: 0.05
          cache_latents_to_disk: false
          resolution: [ {preset.resolution} ]
      train:
        batch_size: 1
        steps: {preset.steps}
        gradient_accumulation: 1
        train_unet: true
        train_text_encoder: false
        gradient_checkpointing: true
        noise_scheduler: "flowmatch"
        timestep_type: "weighted"
        content_or_style: "{preset.content_or_style}"
        optimizer: "adamw8bit"
        optimizer_params:
          weight_decay: 0.0001
        unload_text_encoder: false
        cache_text_embeddings: {bool_text(preset.cache_text_embeddings)}
        lr: {preset.learning_rate}
        ema_config:
          use_ema: false
          ema_decay: 0.99
        skip_first_sample: true
        force_first_sample: false
        disable_sampling: {bool_text(preset.disable_sampling)}
        dtype: "bf16"
        diff_output_preservation: false
        diff_output_preservation_multiplier: 1
        diff_output_preservation_class: "person"
        switch_boundary_every: 1
        loss_type: "mse"
      model:
        name_or_path: {yaml_quote(str(model_dir))}
        quantize: false
        qtype: "qfloat8"
        quantize_te: false
        qtype_te: "qfloat8"
        arch: "zimage:turbo"
        low_vram: {bool_text(preset.low_vram)}
        model_kwargs: {{}}
        layer_offloading: false
        layer_offloading_text_encoder_percent: 1
        layer_offloading_transformer_percent: 1
        assistant_lora_path: {yaml_quote(str(adapter_path))}
      sample:
        sampler: "flowmatch"
        sample_every: {preset.sample_every}
        width: {preset.resolution}
        height: {preset.resolution}
        samples:
          - prompt: {yaml_quote(preset.sample_prompt)}
        neg: ""
        seed: 42
        walk_seed: true
        guidance_scale: {preset.guidance_scale}
        sample_steps: {preset.sample_steps}
        num_frames: 1
        fps: 1
meta:
  name: "[name]"
  version: '1.0'
  nymphs:
    preset_id: {yaml_quote(preset.id)}
"""


def build_job_config_json(
    *,
    name: str,
    dataset_path: Path,
    lora_root: Path,
    db_path: Path,
    model_dir: Path,
    adapter_path: Path,
    preset: Preset,
) -> dict[str, Any]:
    return {
        "job": "extension",
        "config": {
            "name": name,
            "process": [
                {
                    "type": "sd_trainer",
                    "training_folder": str(lora_root),
                    "sqlite_db_path": str(db_path),
                    "device": "cuda:0",
                    "network": {"type": "lora", "linear": preset.rank, "linear_alpha": preset.rank},
                    "save": {
                        "dtype": "bf16",
                        "save_every": preset.save_every,
                        "max_step_saves_to_keep": preset.max_step_saves_to_keep,
                    },
                    "logging": {"log_every": 1, "use_ui_logger": True},
                    "datasets": [
                        {
                            "folder_path": str(dataset_path),
                            "caption_ext": "txt",
                            "caption_dropout_rate": 0.05,
                            "cache_latents_to_disk": False,
                            "resolution": [preset.resolution],
                        }
                    ],
                    "train": {
                        "batch_size": 1,
                        "steps": preset.steps,
                        "gradient_accumulation": 1,
                        "train_unet": True,
                        "train_text_encoder": False,
                        "gradient_checkpointing": True,
                        "noise_scheduler": "flowmatch",
                        "timestep_type": "weighted",
                        "content_or_style": preset.content_or_style,
                        "optimizer": "adamw8bit",
                        "optimizer_params": {"weight_decay": 0.0001},
                        "unload_text_encoder": False,
                        "cache_text_embeddings": preset.cache_text_embeddings,
                        "lr": parse_learning_rate(preset.learning_rate),
                        "ema_config": {"use_ema": False, "ema_decay": 0.99},
                        "skip_first_sample": True,
                        "force_first_sample": False,
                        "disable_sampling": preset.disable_sampling,
                        "dtype": "bf16",
                        "diff_output_preservation": False,
                        "diff_output_preservation_multiplier": 1,
                        "diff_output_preservation_class": "person",
                        "switch_boundary_every": 1,
                        "loss_type": "mse",
                    },
                    "model": {
                        "name_or_path": str(model_dir),
                        "quantize": False,
                        "qtype": "qfloat8",
                        "quantize_te": False,
                        "qtype_te": "qfloat8",
                        "arch": "zimage:turbo",
                        "low_vram": preset.low_vram,
                        "model_kwargs": {},
                        "layer_offloading": False,
                        "layer_offloading_text_encoder_percent": 1,
                        "layer_offloading_transformer_percent": 1,
                        "assistant_lora_path": str(adapter_path),
                    },
                    "sample": {
                        "sampler": "flowmatch",
                        "sample_every": preset.sample_every,
                        "width": preset.resolution,
                        "height": preset.resolution,
                        "samples": [{"prompt": preset.sample_prompt}],
                        "neg": "",
                        "seed": 42,
                        "walk_seed": True,
                        "guidance_scale": preset.guidance_scale,
                        "sample_steps": preset.sample_steps,
                        "num_frames": 1,
                        "fps": 1,
                    },
                }
            ],
        },
        "meta": {"name": "[name]", "version": "1.0", "nymphs": {"preset_id": preset.id}},
    }


def build_lora_metadata(raw_name: str, normalized_name: str, preset: Preset, adapter_version: str) -> dict[str, Any]:
    display_name = raw_name.strip() or normalized_name
    return {
        "schema_version": 1,
        "source": "nymphs_manager",
        "display_name": display_name,
        "activation_text": display_name,
        "auto_use_trigger": bool(display_name),
        "lora_type": "style" if preset.content_or_style == "style" else "character",
        "easy_lora": {
            "preset": preset.id,
            "steps": preset.steps,
            "checkpoints": preset.max_step_saves_to_keep,
            "learning_rate": preset.learning_rate,
            "rank": preset.rank,
            "low_vram": preset.low_vram,
            "adapter": adapter_version,
            "sample_prompt": preset.sample_prompt,
        },
        "notes": "Manager default: use the LoRA name itself as activation text.",
    }


def api_request(method: str, path: str, payload: dict[str, Any] | None = None, timeout: float = 10.0) -> Any:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{AITK_BASE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"AI Toolkit API request to {path} failed with HTTP {exc.code}: {body}") from exc

    if not body.strip():
        return None
    return json.loads(body)


def api_healthy() -> bool:
    try:
        api_request("GET", "/api/queue", timeout=3.0)
        api_request("GET", "/api/jobs?job_type=train", timeout=3.0)
        return True
    except Exception:
        return False


def ensure_api_ready(start_ui_path: Path, lora_root: Path, dataset_root: Path) -> None:
    if not api_healthy():
        if not start_ui_path.is_file() or not os.access(start_ui_path, os.X_OK):
            raise SystemExit(f"AI Toolkit launcher missing: {start_ui_path}. Repair LoRA first.")
        print("Starting AI Toolkit for job registration...")
        subprocess.run([str(start_ui_path)], check=True)

    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if api_healthy():
            configure_settings(lora_root, dataset_root)
            return
        time.sleep(0.5)
    raise SystemExit("AI Toolkit API did not become reachable on localhost:8675.")


def configure_settings(lora_root: Path, dataset_root: Path) -> None:
    settings = api_request("GET", "/api/settings") or {}
    current_token = settings.get("HF_TOKEN") or ""
    if settings.get("TRAINING_FOLDER") == str(lora_root) and settings.get("DATASETS_FOLDER") == str(dataset_root):
        return
    api_request(
        "POST",
        "/api/settings",
        {
            "HF_TOKEN": current_token,
            "TRAINING_FOLDER": str(lora_root),
            "DATASETS_FOLDER": str(dataset_root),
        },
    )


def get_job_by_ref(job_ref: str) -> dict[str, Any] | None:
    encoded = urllib.parse.quote(job_ref, safe="")
    response = api_request("GET", f"/api/jobs?job_ref={encoded}")
    return response if isinstance(response, dict) else None


def upsert_job(job_ref: str, job_config: dict[str, Any]) -> str:
    existing = get_job_by_ref(job_ref)
    payload: dict[str, Any] = {
        "name": job_ref,
        "gpu_ids": "0",
        "job_type": "train",
        "job_ref": job_ref,
        "job_config": job_config,
    }
    if existing and existing.get("id"):
        payload["id"] = existing["id"]

    response = api_request("POST", "/api/jobs", payload)
    if not isinstance(response, dict) or not response.get("id"):
        raise SystemExit("AI Toolkit did not return a job ID after saving the job.")
    return str(response["id"])


def parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    return value.strip().lower() in {"1", "true", "yes", "on"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create and register an Easy LoRA AI Toolkit job.")
    parser.add_argument("--lora-name", "--lora_name", dest="lora_name", default="my_first_lora")
    parser.add_argument("--preset", default="baseline")
    parser.add_argument("--adapter", "--adapter-version", "--adapter_version", dest="adapter_version", default="v1")
    parser.add_argument("--steps", type=int, default=None)
    parser.add_argument("--checkpoints", "--checkpoint-count", "--checkpoint_count", dest="checkpoint_count", type=int, default=None)
    parser.add_argument("--learning-rate", "--learning_rate", dest="learning_rate", default=None)
    parser.add_argument("--rank", type=int, default=None)
    parser.add_argument("--low-vram", "--low_vram", dest="low_vram", default=None)
    parser.add_argument("--sample-prompt", "--sample_prompt", dest="sample_prompt", default=None)
    parser.add_argument("--sample-prompt-b64", "--sample_prompt_b64", dest="sample_prompt_b64", default=None)
    parser.add_argument("--register", action="store_true")
    parser.add_argument("--install-root", required=True)
    parser.add_argument("--datasets-root", required=True)
    parser.add_argument("--loras-root", required=True)
    parser.add_argument("--jobs-root", required=True)
    parser.add_argument("--repo-dir", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--adapter-dir", required=True)
    parser.add_argument("--start-ui", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    install_root = Path(args.install_root)
    dataset_root = Path(args.datasets_root)
    lora_root = Path(args.loras_root)
    jobs_root = Path(args.jobs_root)
    repo_dir = Path(args.repo_dir)
    model_dir = Path(args.model_dir)
    adapter_dir = Path(args.adapter_dir)

    metadata = prepare_metadata(dataset_root, args.lora_name, mirror=True)
    if args.register:
        ensure_model_assets(model_dir)
    adapter_version = "v2" if args.adapter_version.lower() == "v2" else "v1"
    adapter_path = ensure_adapter(adapter_dir, adapter_version)
    sample_prompt = decode_sample_prompt(args.sample_prompt_b64) or args.sample_prompt or ""
    preset = apply_overrides(
        resolve_preset(args.preset),
        steps=args.steps,
        learning_rate=args.learning_rate,
        rank=args.rank,
        low_vram=parse_bool(args.low_vram),
        sample_prompt=sample_prompt,
        checkpoint_count=args.checkpoint_count,
    )

    jobs_root.mkdir(parents=True, exist_ok=True)
    lora_output_path = lora_root / metadata.normalized_name
    lora_output_path.mkdir(parents=True, exist_ok=True)
    lora_root.mkdir(parents=True, exist_ok=True)

    db_path = repo_dir / "aitk_db.db"
    job_path = jobs_root / f"{metadata.normalized_name}.yaml"
    lora_metadata_path = lora_output_path / "nymphs_lora.json"

    job_yaml = build_config_yaml(
        name=metadata.normalized_name,
        dataset_path=metadata.dataset_path,
        lora_root=lora_root,
        db_path=db_path,
        model_dir=model_dir,
        adapter_path=adapter_path,
        preset=preset,
    )
    job_config = build_job_config_json(
        name=metadata.normalized_name,
        dataset_path=metadata.dataset_path,
        lora_root=lora_root,
        db_path=db_path,
        model_dir=model_dir,
        adapter_path=adapter_path,
        preset=preset,
    )
    job_path.write_text(job_yaml, encoding="utf-8")
    lora_metadata_path.write_text(
        json.dumps(build_lora_metadata(args.lora_name, metadata.normalized_name, preset, adapter_version), indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"normalized_name={metadata.normalized_name}")
    print(f"job_config={job_path}")
    print(f"dataset={metadata.dataset_path}")
    print(f"metadata={metadata.metadata_path}")
    print(f"lora_output={lora_output_path}")
    print(f"lora_metadata={lora_metadata_path}")
    print(f"image_count={metadata.image_count}")
    print(f"missing_caption_count={metadata.missing_caption_count}")
    print(f"captions_mirrored={metadata.mirrored_count}")
    print(f"preset={preset.id}")
    print(f"steps={preset.steps}")
    print(f"save_every={preset.save_every}")
    print(f"checkpoints={preset.max_step_saves_to_keep}")
    print(f"learning_rate={preset.learning_rate}")
    print(f"rank={preset.rank}")
    print(f"low_vram={bool_text(preset.low_vram)}")
    print(f"adapter_version={adapter_version}")
    print(f"adapter_path={adapter_path}")

    if args.register:
        ensure_api_ready(Path(args.start_ui), lora_root, dataset_root)
        job_id = upsert_job(metadata.normalized_name, job_config)
        print(f"aitk_job_id={job_id}")
        print(f"Registered '{metadata.normalized_name}' in the AI Toolkit jobs list.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

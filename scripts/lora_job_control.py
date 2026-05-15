#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import time
import urllib.parse
from pathlib import Path
from typing import Any

from lora_dataset import normalize_name
from lora_job import api_healthy, api_request, configure_settings, get_job_by_ref


STRUCTURED_PROGRESS_RE = re.compile(r"TRAIN_PROGRESS\s+current=(?P<current>\d+)\s+total=(?P<total>\d+)")
STEP_PROGRESS_RE = re.compile(r"(?P<current>\d+)\s*/\s*(?P<total>\d+)")
PERCENT_RE = re.compile(r"(?P<percent>\d{1,3})%")
YAML_STEPS_RE = re.compile(r"^\s*steps:\s*(?P<value>\d+)\s*$", re.MULTILINE)
YAML_DATASET_RE = re.compile(r"^\s*-\s*folder_path:\s*['\"]?(?P<value>[^'\"\r\n#]+)", re.MULTILINE)
YAML_PRESET_RE = re.compile(r"^\s*#\s*nymphs_preset_id:\s*(?P<value>[^\r\n#]+)", re.MULTILINE)
YAML_LEARNING_RATE_RE = re.compile(r"^\s*lr:\s*(?P<value>[^\s#]+)\s*$", re.MULTILINE)
YAML_RANK_RE = re.compile(r"^\s*linear:\s*(?P<value>\d+)\s*$", re.MULTILINE)
YAML_CONTENT_STYLE_RE = re.compile(r"^\s*content_or_style:\s*[\"']?(?P<value>[^\"'\r\n#]+)", re.MULTILINE)
YAML_LOW_VRAM_RE = re.compile(r"^\s*low_vram:\s*(?P<value>true|false)\s*$", re.MULTILINE | re.IGNORECASE)
YAML_SAVE_EVERY_RE = re.compile(r"^\s*save_every:\s*(?P<value>\d+)\s*$", re.MULTILINE)
YAML_MAX_SAVES_RE = re.compile(r"^\s*max_step_saves_to_keep:\s*(?P<value>\d+)\s*$", re.MULTILINE)
YAML_ADAPTER_PATH_RE = re.compile(r"^\s*assistant_lora_path:\s*[\"']?(?P<value>[^\"'\r\n#]+)", re.MULTILINE)
YAML_SAMPLE_PROMPT_RE = re.compile(r"^\s*-\s*prompt:\s*(?P<value>.*?)\s*$", re.MULTILINE)


def ensure_api_ready(
    start_ui_path: Path,
    start_worker_path: Path,
    lora_root: Path,
    dataset_root: Path,
    *,
    allow_launch: bool,
) -> None:
    if allow_launch and start_worker_path.is_file() and start_worker_path.stat().st_mode & 0o111:
        subprocess.run([str(start_worker_path)], check=True)

    if not api_healthy():
        if not allow_launch:
            raise SystemExit("AI Toolkit is not running. Open AI Toolkit first, then try again.")
        if not start_ui_path.is_file() or not start_ui_path.stat().st_mode & 0o111:
            raise SystemExit(f"AI Toolkit launcher missing: {start_ui_path}. Repair LoRA first.")
        print("Starting AI Toolkit...")
        subprocess.run([str(start_ui_path)], check=True)

    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if api_healthy():
            configure_settings(lora_root, dataset_root)
            return
        time.sleep(0.5)
    raise SystemExit("AI Toolkit API did not become reachable on localhost:8675.")


def get_job_by_id(job_id: str) -> dict[str, Any] | None:
    encoded = urllib.parse.quote(job_id, safe="")
    response = api_request("GET", f"/api/jobs?id={encoded}")
    return response if isinstance(response, dict) else None


def get_active_train_job() -> dict[str, Any] | None:
    response = api_request("GET", "/api/jobs?job_type=train")
    if not isinstance(response, dict):
        return None

    jobs = response.get("jobs")
    if not isinstance(jobs, list):
        return None

    running_job = None
    queued_job = None
    for job in jobs:
        if not isinstance(job, dict):
            continue
        status = str(job.get("status") or "").lower()
        if running_job is None and status == "running":
            running_job = job
            continue
        if queued_job is None and status == "queued":
            queued_job = job

    return running_job or queued_job


def get_job_log(job_id: str) -> str:
    encoded = urllib.parse.quote(job_id, safe="")
    response = api_request("GET", f"/api/jobs/{encoded}/log")
    if isinstance(response, dict):
        return str(response.get("log") or "")
    return ""


def parse_progress_from_log(log_text: str, expected_total: int) -> tuple[int, int, int, str]:
    current = 0
    total = max(0, expected_total)
    percent = 0
    stage = "No training progress found yet."

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        lower = line.lower()

        structured = STRUCTURED_PROGRESS_RE.search(line)
        if structured:
            current = int(structured.group("current"))
            total = int(structured.group("total"))
            percent = round(current * 100 / total) if total > 0 else 0
            stage = f"Training progress: {current}/{total} steps"
            continue

        step_match = STEP_PROGRESS_RE.search(line)
        if step_match:
            candidate_current = int(step_match.group("current"))
            candidate_total = int(step_match.group("total"))
            if candidate_total > 0 and (expected_total <= 0 or candidate_total == expected_total):
                current = candidate_current
                total = candidate_total
                percent = round(current * 100 / total)
                stage = f"Training progress: {current}/{total} steps"
                continue

        if "loading model" in lower or "loading transformer" in lower:
            percent = max(percent, 4)
            stage = "Loading Z-Image model..."
        elif "assistant" in lower and "lora" in lower:
            percent = max(percent, 6)
            stage = "Loading assistant adapter..."
        elif "preparing dataset" in lower:
            percent = max(percent, 10)
            stage = "Preparing dataset..."
        elif "bucketing" in lower:
            percent = max(percent, 12)
            stage = "Bucketing dataset..."
        elif "sampling" in lower and "first" in lower:
            percent = max(percent, 14)
            stage = "Rendering baseline preview..."

        percent_match = PERCENT_RE.search(line)
        if percent_match and current == 0:
            parsed_percent = max(0, min(100, int(percent_match.group("percent"))))
            percent = max(percent, parsed_percent)
            stage = f"Training progress: {percent}%"

    if total > 0 and current >= total:
        percent = 100
        stage = f"Training completed: {total}/{total} steps"

    return current, total, max(0, min(100, percent)), stage


def read_yaml_steps(job_path: Path) -> int:
    if not job_path.is_file():
        return 0
    match = YAML_STEPS_RE.search(job_path.read_text(encoding="utf-8", errors="replace"))
    return int(match.group("value")) if match else 0


def read_yaml_dataset_name(job_path: Path) -> str:
    if not job_path.is_file():
        return ""
    text = job_path.read_text(encoding="utf-8", errors="replace")
    match = YAML_DATASET_RE.search(text)
    if not match:
        return ""
    return Path(match.group("value").strip().rstrip("/")).name


def parse_match_int(regex: re.Pattern[str], text: str) -> int:
    match = regex.search(text)
    if not match:
        return 0
    try:
        return int(match.group("value"))
    except ValueError:
        return 0


def parse_match_bool(regex: re.Pattern[str], text: str) -> bool:
    match = regex.search(text)
    return bool(match and match.group("value").strip().lower() == "true")


def parse_match_string(regex: re.Pattern[str], text: str) -> str:
    match = regex.search(text)
    return match.group("value").strip() if match else ""


def normalize_learning_rate(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return "1e-4"
    try:
        parsed = float(raw)
    except ValueError:
        return raw.lower()
    known = {
        0.0001: "1e-4",
        0.00005: "5e-5",
        0.0002: "2e-4",
    }
    for number, label in known.items():
        if abs(parsed - number) < 0.000000001:
            return label
    return raw


def int_value(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def normalize_sample_prompt(prompt: str) -> str:
    trimmed = (prompt or "").strip()
    if not trimmed:
        return ""
    if (trimmed.startswith("'") and trimmed.endswith("'")) or (
        trimmed.startswith('"') and trimmed.endswith('"')
    ):
        trimmed = trimmed[1:-1]
    return trimmed.replace("''", "'").strip()


def infer_preset_id(content_or_style: str) -> str:
    normalized = (content_or_style or "").strip().lower()
    if normalized == "content":
        return "strong_style"
    if normalized == "style":
        return "style"
    return "baseline"


def compute_checkpoint_count(steps: int, save_every: int, max_saves: int) -> int:
    if steps <= 0 or save_every <= 0 or max_saves <= 0:
        return 0
    derived = max(1, round(steps / save_every))
    return max(1, min(max_saves, derived))


def adapter_version_from_path(path: str) -> str:
    return "v2" if "_v2" in (path or "").lower() else "v1"


def read_job_settings_from_metadata(lora_metadata: dict[str, Any]) -> dict[str, Any]:
    settings = lora_metadata.get("easy_lora")
    if not isinstance(settings, dict):
        return {}
    return {
        "preset": str(settings.get("preset") or "baseline"),
        "steps": int_value(settings.get("steps"), 3000),
        "checkpoints": int_value(settings.get("checkpoints"), 0),
        "learning_rate": normalize_learning_rate(settings.get("learning_rate")),
        "rank": int_value(settings.get("rank"), 16),
        "low_vram": bool_value(settings.get("low_vram")),
        "adapter": "v2" if str(settings.get("adapter") or "").lower() == "v2" else "v1",
        "sample_prompt": str(settings.get("sample_prompt") or ""),
        "source": "metadata",
    }


def read_job_settings_from_yaml(job_path: Path) -> dict[str, Any]:
    if not job_path.is_file():
        return {}
    text = job_path.read_text(encoding="utf-8", errors="replace")
    steps = parse_match_int(YAML_STEPS_RE, text) or 3000
    save_every = parse_match_int(YAML_SAVE_EVERY_RE, text)
    max_saves = parse_match_int(YAML_MAX_SAVES_RE, text)
    content_or_style = parse_match_string(YAML_CONTENT_STYLE_RE, text)
    adapter_path = parse_match_string(YAML_ADAPTER_PATH_RE, text)
    preset = parse_match_string(YAML_PRESET_RE, text) or infer_preset_id(content_or_style)
    return {
        "preset": preset,
        "steps": steps,
        "checkpoints": compute_checkpoint_count(steps, save_every, max_saves),
        "learning_rate": normalize_learning_rate(parse_match_string(YAML_LEARNING_RATE_RE, text)),
        "rank": parse_match_int(YAML_RANK_RE, text) or 16,
        "low_vram": parse_match_bool(YAML_LOW_VRAM_RE, text),
        "adapter": adapter_version_from_path(adapter_path),
        "sample_prompt": normalize_sample_prompt(parse_match_string(YAML_SAMPLE_PROMPT_RE, text)),
        "source": "yaml",
    }


def object_property(value: Any, key: str) -> Any:
    return value.get(key) if isinstance(value, dict) else None


def first_process(job_config: Any) -> dict[str, Any]:
    if isinstance(job_config, str):
        try:
            job_config = json.loads(job_config)
        except Exception:
            return {}
    if not isinstance(job_config, dict):
        return {}
    config = object_property(job_config, "config")
    processes = object_property(config, "process")
    if not isinstance(processes, list) or not processes:
        return {}
    return processes[0] if isinstance(processes[0], dict) else {}


def sample_prompt_from_config(sample: Any) -> str:
    samples = object_property(sample, "samples")
    if not isinstance(samples, list) or not samples:
        return ""
    first_sample = samples[0]
    if not isinstance(first_sample, dict):
        return ""
    return str(first_sample.get("prompt") or "")


def read_job_settings_from_config(job_config: Any) -> dict[str, Any]:
    process = first_process(job_config)
    if not process:
        return {}
    train = object_property(process, "train")
    network = object_property(process, "network")
    model = object_property(process, "model")
    save = object_property(process, "save")
    sample = object_property(process, "sample")

    root = json.loads(job_config) if isinstance(job_config, str) else job_config
    meta = object_property(root, "meta")
    nymphs = object_property(meta, "nymphs")
    content_or_style = str(object_property(train, "content_or_style") or "balanced")
    preset = str(object_property(nymphs, "preset_id") or infer_preset_id(content_or_style))
    steps = int_value(object_property(train, "steps"), 3000)
    save_every = int_value(object_property(save, "save_every"), 0)
    max_saves = int_value(object_property(save, "max_step_saves_to_keep"), 0)
    adapter_path = str(object_property(model, "assistant_lora_path") or "")
    return {
        "preset": preset,
        "steps": steps,
        "checkpoints": compute_checkpoint_count(steps, save_every, max_saves),
        "learning_rate": normalize_learning_rate(object_property(train, "lr")),
        "rank": int_value(object_property(network, "linear"), 16),
        "low_vram": bool_value(object_property(model, "low_vram")),
        "adapter": adapter_version_from_path(adapter_path),
        "sample_prompt": sample_prompt_from_config(sample),
        "source": "api",
    }


def form_status_fields(settings: dict[str, Any]) -> dict[str, Any]:
    return {
        "form_settings_exists": bool(settings),
        "form_settings_source": str(settings.get("source") or ""),
        "form_preset": str(settings.get("preset") or ""),
        "form_steps": int_value(settings.get("steps"), 0),
        "form_checkpoints": int_value(settings.get("checkpoints"), 0),
        "form_learning_rate": str(settings.get("learning_rate") or ""),
        "form_rank": int_value(settings.get("rank"), 0),
        "form_low_vram": bool_value(settings.get("low_vram")),
        "form_adapter": str(settings.get("adapter") or ""),
        "form_sample_prompt": str(settings.get("sample_prompt") or ""),
    }


def final_checkpoint_path(lora_root: Path, normalized_lora: str) -> Path:
    return lora_root / normalized_lora / f"{normalized_lora}.safetensors"


def file_size(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def file_modified_iso(path: Path) -> str:
    try:
        timestamp = path.stat().st_mtime
    except OSError:
        return ""
    return dt.datetime.fromtimestamp(timestamp, tz=dt.timezone.utc).isoformat()


def read_lora_metadata(lora_output_path: Path) -> dict[str, Any]:
    metadata_path = lora_output_path / "nymphs_lora.json"
    if not metadata_path.is_file():
        return {}
    try:
        payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return payload if isinstance(payload, dict) else {}


def discover_finished_loras(lora_root: Path) -> list[dict[str, Any]]:
    if not lora_root.is_dir():
        return []

    finished: list[dict[str, Any]] = []
    for path in lora_root.rglob("*.safetensors"):
        if not path.is_file():
            continue
        output_dir = path.parent
        metadata = read_lora_metadata(output_dir)
        finished.append(
            {
                "name": path.stem,
                "path": str(path),
                "size": file_size(path),
                "modified": file_modified_iso(path),
                "display_name": str(metadata.get("display_name") or path.stem),
                "activation_text": str(metadata.get("activation_text") or ""),
                "lora_type": str(metadata.get("lora_type") or ""),
            }
        )

    finished.sort(key=lambda item: str(item.get("modified") or ""), reverse=True)
    return finished


def wait_for_live_state(job_id: str) -> dict[str, Any] | None:
    deadline = time.monotonic() + 10
    last_seen: dict[str, Any] | None = None
    while time.monotonic() < deadline:
        last_seen = get_job_by_id(job_id)
        if not last_seen:
            time.sleep(0.5)
            continue

        status = str(last_seen.get("status") or "").lower()
        if status in {"queued", "running"}:
            return last_seen
        if status in {"error", "failed", "stopped"}:
            info = last_seen.get("info") or "Unknown AI Toolkit job failure."
            raise SystemExit(f"AI Toolkit reported job state '{status}': {info}")
        time.sleep(0.5)
    return last_seen


def start_job(args: argparse.Namespace) -> int:
    normalized_lora = normalize_name(args.lora_name, "LoRA")
    lora_root = Path(args.loras_root)
    dataset_root = Path(args.datasets_root)
    ensure_api_ready(Path(args.start_ui), Path(args.start_worker), lora_root, dataset_root, allow_launch=True)

    job = get_job_by_ref(normalized_lora)
    if not job or not job.get("id"):
        raise SystemExit(f"No AI Toolkit job was found for '{normalized_lora}'. Create Job first.")

    job_id = str(job["id"])
    gpu_ids = str(job.get("gpu_ids") or "").strip()
    if not gpu_ids:
        raise SystemExit("AI Toolkit job does not have a valid GPU/queue assignment.")

    encoded = urllib.parse.quote(job_id, safe="")
    api_request("GET", f"/api/jobs/{encoded}/start")
    live_job = wait_for_live_state(job_id)
    status = str((live_job or {}).get("status") or "unknown")
    if status.lower() not in {"queued", "running"}:
        raise SystemExit("AI Toolkit did not keep the job in a queued or running state.")

    print(f"normalized_name={normalized_lora}")
    print(f"aitk_job_id={job_id}")
    print(f"gpu_ids={gpu_ids}")
    print(f"status={status}")
    print(f"Queued '{normalized_lora}' in the AI Toolkit queue on GPU target {gpu_ids}.")
    return 0


def stop_job(args: argparse.Namespace) -> int:
    lora_root = Path(args.loras_root)
    dataset_root = Path(args.datasets_root)
    ensure_api_ready(Path(args.start_ui), Path(args.start_worker), lora_root, dataset_root, allow_launch=False)

    job = get_active_train_job()
    if not job or not job.get("id"):
        print("active_state=idle")
        print("No active Z-Image Trainer job was found.")
        return 0

    job_id = str(job["id"])
    status = str(job.get("status") or "").lower()
    encoded = urllib.parse.quote(job_id, safe="")
    if status == "queued":
        endpoint = f"/api/jobs/{encoded}/mark_stopped"
    else:
        endpoint = f"/api/jobs/{encoded}/stop"

    api_request("GET", endpoint)
    print(f"aitk_job_id={job_id}")
    print(f"previous_status={status or 'unknown'}")
    print("stop_requested=true")
    print("Stop requested for the active AI Toolkit job.")
    return 0


def delete_job(args: argparse.Namespace) -> int:
    normalized_lora = normalize_name(args.lora_name, "LoRA")
    lora_root = Path(args.loras_root)
    dataset_root = Path(args.datasets_root)
    ensure_api_ready(Path(args.start_ui), Path(args.start_worker), lora_root, dataset_root, allow_launch=False)

    job = get_job_by_ref(normalized_lora)
    if not job or not job.get("id"):
        raise SystemExit(f"No AI Toolkit job was found for '{normalized_lora}'.")

    job_id = str(job["id"])
    encoded = urllib.parse.quote(job_id, safe="")
    api_request("GET", f"/api/jobs/{encoded}/delete")
    print(f"normalized_name={normalized_lora}")
    print(f"aitk_job_id={job_id}")
    print(f"Deleted AI Toolkit job '{normalized_lora}'.")
    return 0


def job_status(args: argparse.Namespace) -> int:
    normalized_lora = normalize_name(args.lora_name, "LoRA")
    jobs_root = Path(args.jobs_root)
    lora_root = Path(args.loras_root)
    dataset_root = Path(args.datasets_root)
    job_path = jobs_root / f"{normalized_lora}.yaml"
    final_path = final_checkpoint_path(lora_root, normalized_lora)
    lora_output_path = lora_root / normalized_lora
    lora_metadata = read_lora_metadata(lora_output_path)
    finished_loras = discover_finished_loras(lora_root)
    latest_finished = finished_loras[0] if finished_loras else {}
    expected_total = read_yaml_steps(job_path)
    form_settings = read_job_settings_from_metadata(lora_metadata) or read_job_settings_from_yaml(job_path)
    dataset_name = read_yaml_dataset_name(job_path) or normalized_lora
    metadata_path = dataset_root / dataset_name / "metadata.csv"
    final_exists = final_path.is_file()

    status: dict[str, Any] = {
        "normalized_name": normalized_lora,
        "api_running": False,
        "job_exists": False,
        "job_id": "",
        "job_status": "",
        "job_info": "",
        "gpu_ids": "",
        "local_job_config": str(job_path),
        "local_job_config_exists": job_path.is_file(),
        "dataset_name": dataset_name,
        "metadata": str(metadata_path),
        "metadata_exists": metadata_path.is_file(),
        "final_checkpoint": str(final_path),
        "final_checkpoint_exists": final_exists,
        "final_checkpoint_size": file_size(final_path),
        "final_checkpoint_modified": file_modified_iso(final_path),
        "lora_metadata": str(lora_output_path / "nymphs_lora.json"),
        "lora_metadata_exists": (lora_output_path / "nymphs_lora.json").is_file(),
        "display_name": str(lora_metadata.get("display_name") or normalized_lora),
        "activation_text": str(lora_metadata.get("activation_text") or ""),
        "lora_type": str(lora_metadata.get("lora_type") or ""),
        "finished_lora_count": len(finished_loras),
        "latest_finished_lora": str(latest_finished.get("path") or ""),
        "latest_finished_lora_name": str(latest_finished.get("display_name") or latest_finished.get("name") or ""),
        "latest_finished_lora_size": latest_finished.get("size", 0) if latest_finished else 0,
        "latest_finished_lora_modified": str(latest_finished.get("modified") or ""),
        "finished_loras_json": json.dumps(finished_loras[:20]),
        "progress_current": 0,
        "progress_total": expected_total,
        "progress_percent": 100 if final_exists else 0,
        "progress_text": "Training completed." if final_exists else "No training run in progress yet.",
        "log_available": False,
        "log_tail": "",
    }
    status.update(form_status_fields(form_settings))

    if api_healthy():
        status["api_running"] = True
        configure_settings(lora_root, dataset_root)
        job = get_job_by_ref(normalized_lora)
        if job:
            job_id = str(job.get("id") or "")
            status.update(
                {
                    "job_exists": True,
                    "job_id": job_id,
                    "job_status": str(job.get("status") or ""),
                    "job_info": str(job.get("info") or ""),
                    "gpu_ids": str(job.get("gpu_ids") or ""),
                }
            )
            api_form_settings = read_job_settings_from_config(job.get("job_config"))
            if api_form_settings:
                status.update(form_status_fields(api_form_settings))
            if job_id:
                log_text = get_job_log(job_id)
                if log_text:
                    current, total, percent, text = parse_progress_from_log(log_text, expected_total)
                    status.update(
                        {
                            "log_available": True,
                            "progress_current": current,
                            "progress_total": total,
                            "progress_percent": 100 if final_exists else percent,
                            "progress_text": "Training completed." if final_exists else text,
                            "log_tail": "\n".join(log_text.splitlines()[-40:]),
                        }
                    )

    for key, value in status.items():
        if isinstance(value, bool):
            print(f"{key}={'true' if value else 'false'}")
        elif key == "log_tail":
            print("log_tail_json=" + json.dumps(value))
        elif key == "form_sample_prompt":
            print("form_sample_prompt_json=" + json.dumps(value))
        elif key == "finished_loras_json":
            print("finished_loras_json=" + str(value))
        else:
            print(f"{key}={value}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Control Easy LoRA AI Toolkit jobs.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in ("start", "stop", "delete", "status"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--lora-name", "--lora_name", dest="lora_name", default="my_first_lora")
        command_parser.add_argument("--datasets-root", required=True)
        command_parser.add_argument("--loras-root", required=True)
        command_parser.add_argument("--jobs-root", required=True)
        command_parser.add_argument("--start-ui", required=True)
        command_parser.add_argument("--start-worker", required=True)

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "start":
        return start_job(args)
    if args.command == "stop":
        return stop_job(args)
    if args.command == "delete":
        return delete_job(args)
    if args.command == "status":
        return job_status(args)
    raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())

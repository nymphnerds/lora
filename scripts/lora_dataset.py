#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}


@dataclass(frozen=True)
class MetadataStatus:
    normalized_name: str
    dataset_path: Path
    metadata_path: Path
    image_count: int
    missing_caption_count: int
    mirrored_count: int


def normalize_name(value: str, label: str) -> str:
    trimmed = value.strip()
    if not trimmed:
        raise ValueError(f"Enter a {label} name.")

    chars: list[str] = []
    for char in trimmed:
        if char.isalnum() or char in "_-":
            chars.append(char)
        elif char.isspace():
            chars.append("_")

    normalized = "".join(chars).strip("_-")
    if not normalized:
        raise ValueError(f"Enter a {label} name using letters, numbers, spaces, dashes, or underscores.")
    return normalized


def read_metadata(metadata_path: Path) -> dict[str, str]:
    captions: dict[str, str] = {}
    if not metadata_path.exists():
        return captions

    with metadata_path.open("r", encoding="utf-8", newline="") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        has_header = bool(re.search(r"(?im)^\s*(image|file_name)\s*,", sample))
        if has_header:
            reader = csv.DictReader(handle)
            for row in reader:
                image = (row.get("image") or row.get("file_name") or "").strip()
                prompt = row.get("prompt") or row.get("text") or row.get("caption") or ""
                if image:
                    captions[image.lower()] = prompt
            return captions

        reader = csv.reader(handle)
        for row in reader:
            if not row or not row[0].strip():
                continue
            captions[row[0].strip().lower()] = row[1] if len(row) > 1 else ""

    return captions


def write_metadata(metadata_path: Path, rows: list[tuple[str, str]]) -> None:
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    with metadata_path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("image,prompt\n")
        writer = csv.writer(handle, quoting=csv.QUOTE_ALL)
        for image, prompt in rows:
            writer.writerow((image, prompt.replace("\r", " ").replace("\n", " ")))


def image_files(dataset_path: Path) -> list[Path]:
    if not dataset_path.exists():
        return []
    return sorted(
        (
            path
            for path in dataset_path.iterdir()
            if path.is_file() and path.suffix.lower() in SUPPORTED_IMAGE_EXTENSIONS
        ),
        key=lambda path: path.name.lower(),
    )


def sync_caption_text_files(dataset_path: Path, rows: list[tuple[str, str]]) -> int:
    mirrored = 0
    for image_name, caption in rows:
        image_path = dataset_path / image_name
        if not image_path.is_file():
            continue
        caption_path = image_path.with_suffix(".txt")
        caption_path.write_text(
            caption.replace("\r", " ").replace("\n", " ").strip(),
            encoding="utf-8",
        )
        mirrored += 1
    return mirrored


def prepare_metadata(datasets_root: Path, raw_name: str, *, mirror: bool) -> MetadataStatus:
    normalized = normalize_name(raw_name, "LoRA")
    dataset_path = datasets_root / normalized
    metadata_path = dataset_path / "metadata.csv"
    dataset_path.mkdir(parents=True, exist_ok=True)

    existing_captions = read_metadata(metadata_path)
    rows = [
        (image_path.name, existing_captions.get(image_path.name.lower(), ""))
        for image_path in image_files(dataset_path)
    ]
    write_metadata(metadata_path, rows)

    mirrored_count = sync_caption_text_files(dataset_path, rows) if mirror else 0
    missing_caption_count = sum(1 for _, caption in rows if not caption.strip())
    return MetadataStatus(
        normalized_name=normalized,
        dataset_path=dataset_path,
        metadata_path=metadata_path,
        image_count=len(rows),
        missing_caption_count=missing_caption_count,
        mirrored_count=mirrored_count,
    )


def print_status(status: MetadataStatus) -> None:
    print(f"normalized_name={status.normalized_name}")
    print(f"directory={status.dataset_path}")
    print(f"metadata={status.metadata_path}")
    print(f"image_count={status.image_count}")
    print(f"missing_caption_count={status.missing_caption_count}")
    print(f"captions_mirrored={status.mirrored_count}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Easy LoRA dataset and caption metadata helper.")
    parser.add_argument("command", choices=("pictures", "captions", "prepare"))
    parser.add_argument("--datasets-root", required=True)
    parser.add_argument("--lora-name", "--lora_name", dest="lora_name", default="my_first_lora")
    parser.add_argument("--dataset-name", "--dataset_name", dest="dataset_name", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_name = args.dataset_name.strip() or args.lora_name.strip()
    datasets_root = Path(args.datasets_root).expanduser()

    if args.command == "pictures":
        normalized = normalize_name(raw_name, "LoRA")
        dataset_path = datasets_root / normalized
        dataset_path.mkdir(parents=True, exist_ok=True)
        print(f"normalized_name={normalized}")
        print(f"directory={dataset_path}")
        return 0

    status = prepare_metadata(datasets_root, raw_name, mirror=True)
    print_status(status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

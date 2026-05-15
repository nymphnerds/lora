#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import csv
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image


SUPPORTED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
MAX_CAPTION_IMAGE_DIMENSION = 1024
STYLE_MEDIUM_PATTERN = re.compile(
    r"\b(?:watercolor|watercolour|oil painting|oil-painted|oil paint|painting|painted|painterly|illustration|illustrative|artwork|gouache|acrylic|pastel|sketch|ink drawing|line art|concept art|digital art)\b",
    flags=re.IGNORECASE,
)
STYLE_FLUFF_PATTERN = re.compile(
    r"\b(?:serene|vibrant|tranquil|peaceful|beautiful|stunning|dramatic|moody|dreamy|ethereal|abstract|colorful|radiant|glowing|picturesque)\b",
    flags=re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Draft metadata.csv captions for a Z-Image dataset with a Brain vision model."
    )
    parser.add_argument("--dataset-dir", required=True)
    parser.add_argument("--metadata-path", required=True)
    parser.add_argument("--mode", choices=("fill_blanks", "overwrite_all"), default="fill_blanks")
    parser.add_argument("--training-focus", choices=("character", "style"), default="character")
    parser.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    return parser.parse_args()


def load_model_id(endpoint: str) -> str:
    parsed = urllib.parse.urlsplit(endpoint)
    path = parsed.path or ""

    if path.endswith("/chat/completions"):
        path = path[: -len("/chat/completions")] + "/models"
    elif path.endswith("/completions"):
        path = path[: -len("/completions")] + "/models"
    else:
        path = path.rstrip("/") + "/models"

    models_endpoint = urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, path, parsed.query, parsed.fragment)
    )
    request = urllib.request.Request(models_endpoint, method="GET")
    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.loads(response.read().decode("utf-8"))

    for item in payload.get("data", []):
        model_id = str(item.get("id", "")).strip()
        if model_id:
            return model_id

    return "local-model"


def read_metadata(metadata_path: Path, dataset_dir: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    existing_by_name: dict[str, str] = {}

    if metadata_path.exists():
        with metadata_path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                file_name = (row.get("image") or row.get("file_name") or "").strip()
                text = (row.get("prompt") or row.get("text") or row.get("caption") or "").strip()
                if not file_name:
                    continue
                rows.append({"image": file_name, "prompt": text})
                existing_by_name[file_name] = text

    disk_images = sorted(
        path.name
        for path in dataset_dir.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )

    if rows:
        row_names = {row["image"] for row in rows}
        for file_name in disk_images:
            if file_name not in row_names:
                rows.append({"image": file_name, "prompt": existing_by_name.get(file_name, "")})
        rows = [row for row in rows if (dataset_dir / row["image"]).is_file()]
        return rows

    return [{"image": file_name, "prompt": ""} for file_name in disk_images]


def write_metadata(metadata_path: Path, rows: list[dict[str, str]]) -> None:
    with metadata_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=("image", "prompt"))
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "image": row["image"],
                    "prompt": row["prompt"].strip(),
                }
            )


def build_prompt(training_focus: str) -> str:
    if training_focus == "style":
        return (
            "Write one short natural training caption for this image. Describe the visible scene, subject, setting, and action clearly. "
            "This is for a stylized look LoRA, so the caption should mostly describe content, not artistic style. "
            "Caption it more like a plain reference photo of the same scene, even if the image itself is stylized. "
            "Avoid naming the medium or style with phrases like watercolor, watercolour, painting, painted, oil painting, brushwork, painterly, woodblock, woodblock print, wood blockprint, wood block print, traditional Japanese style, Japanese woodblock print, illustration, illustration style, concept art, digital art, or artwork unless absolutely necessary to identify visible subject matter. "
            "Avoid quality words and tag soup. Prefer simple concrete nouns and verbs. "
            "Good example: mount fuji beyond a calm lake with shoreline trees. "
            "Output one caption line only and do not wrap it in quotes."
        )

    return (
        "Write one short natural training caption for this image. Focus on the main subject and visible distinguishing traits. "
        "Keep it concise, concrete, and prompt-like. Do not wrap the answer in quotes. Output one caption line only."
    )


def build_style_retry_prompt(previous_caption: str) -> str:
    return (
        "Rewrite the training caption for this image so it describes only visible content. "
        "Do not mention medium, style, mood, beauty, or abstraction words. "
        "Do not use words like watercolor, painting, painted, illustration, artwork, abstract, serene, vibrant, glowing, colorful, or picturesque. "
        "Name only concrete visible things such as people, dogs, boats, trees, flowers, village, hills, river, lake, clouds, dock, road, tunnel, sunset, or ocean when they are actually present. "
        f"Previous caption to fix: {previous_caption}. "
        "Return one short plain caption line only, with no quotes."
    )


def build_style_retry_prompt_v2(previous_caption: str) -> str:
    return (
        "Look at the image and write a short training caption using only concrete visible content. "
        "Avoid medium, style, quality, mood, and abstraction language entirely. "
        "Prefer plain scene wording like 'boats on calm water at sunset' or 'village road with trees and hills'. "
        "Do not use words like watercolor, painting, painted, illustration, artwork, abstract, serene, vibrant, glowing, colorful, picturesque, beautiful, or dramatic. "
        f"Bad previous caption: {previous_caption}. "
        "Return one plain caption line only, with no quotes."
    )


def encode_image(image_path: Path) -> str:
    with Image.open(image_path) as image:
        normalized = image.convert("RGB")
        normalized.thumbnail(
            (MAX_CAPTION_IMAGE_DIMENSION, MAX_CAPTION_IMAGE_DIMENSION),
            Image.LANCZOS,
        )
        buffer = BytesIO()
        normalized.save(buffer, format="JPEG", quality=88, optimize=True)

    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    return f"data:image/jpeg;base64,{encoded}"


def extract_caption_text(payload: dict) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("Caption Brain API response did not include any choices.")

    message = choices[0].get("message", {})
    content = message.get("content")

    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            text = item.get("text")
            if isinstance(text, str) and text.strip():
                parts.append(text.strip())
        if parts:
            return " ".join(parts)

    raise ValueError("Caption Brain API response did not include usable text content.")


def clean_caption(text: str) -> str:
    cleaned = re.sub(r"\s+", " ", text).strip()
    cleaned = re.sub(r"^caption\s*:\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = cleaned.strip().strip("\"' ")
    return cleaned


def clean_style_caption(text: str) -> str:
    original = clean_caption(text)
    cleaned = STYLE_MEDIUM_PATTERN.sub("", original)
    cleaned = STYLE_FLUFF_PATTERN.sub("", cleaned)
    cleaned = re.sub(r"\s+,", ",", cleaned)
    cleaned = re.sub(r",\s*,+", ", ", cleaned)
    cleaned = re.sub(r"\bwith\s+and\b", "with", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\band\s+and\b", "and", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s{2,}", " ", cleaned)
    cleaned = cleaned.strip(" ,.-")
    return cleaned if len(cleaned.split()) >= 3 else original


def style_caption_needs_retry(text: str) -> bool:
    cleaned = clean_caption(text)
    return bool(STYLE_MEDIUM_PATTERN.search(cleaned) or STYLE_FLUFF_PATTERN.search(cleaned))


def style_caption_penalty(text: str) -> int:
    cleaned = clean_caption(text)
    medium_hits = len(STYLE_MEDIUM_PATTERN.findall(cleaned))
    fluff_hits = len(STYLE_FLUFF_PATTERN.findall(cleaned))
    short_penalty = 5 if len(cleaned.split()) < 3 else 0
    return medium_hits * 10 + fluff_hits * 4 + short_penalty


def choose_best_style_caption(candidates: list[str]) -> str:
    def score(text: str) -> tuple[int, int]:
        cleaned = clean_style_caption(text)
        return (style_caption_penalty(text), -len(cleaned.split()))

    best = min(candidates, key=score)
    return clean_style_caption(best)


def build_caption_payload(
    model_id: str,
    prompt: str,
    image_data_url: str,
    *,
    use_object_image_url: bool,
    include_system_prompt: bool,
) -> dict:
    image_part: dict[str, object]
    if use_object_image_url:
        image_part = {
            "type": "image_url",
            "image_url": {
                "url": image_data_url,
            },
        }
    else:
        image_part = {
            "type": "image_url",
            "image_url": image_data_url,
        }

    messages: list[dict[str, object]] = []
    if include_system_prompt:
        messages.append(
            {
                "role": "system",
                "content": (
                    "You write concise, useful LoRA training captions. "
                    "Answer with one plain caption line only."
                ),
            }
        )

    messages.append(
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                image_part,
            ],
        }
    )

    return {
        "model": model_id,
        "temperature": 0.2,
        "max_tokens": 120,
        "messages": messages,
    }


def post_caption_request(endpoint: str, payload: dict, training_focus: str) -> str:
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Caption Brain API returned HTTP {exc.code}. {error_body}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Caption Brain could not reach the local Brain endpoint. {exc}") from exc

    try:
        response_payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Caption Brain returned invalid JSON: {body[:240]}") from exc

    caption = extract_caption_text(response_payload)
    if training_focus == "style":
        return clean_style_caption(caption)
    return clean_caption(caption)


def request_caption(endpoint: str, model_id: str, prompt: str, image_path: Path, training_focus: str) -> str:
    image_data_url = encode_image(image_path)

    attempts = [
        (True, True),
        (False, True),
        (True, False),
    ]

    def run_attempts(prompt_text: str) -> str:
        last_error: RuntimeError | None = None

        for use_object_image_url, include_system_prompt in attempts:
            payload = build_caption_payload(
                model_id,
                prompt_text,
                image_data_url,
                use_object_image_url=use_object_image_url,
                include_system_prompt=include_system_prompt,
            )
            try:
                return post_caption_request(endpoint, payload, training_focus)
            except RuntimeError as exc:
                last_error = exc
                message = str(exc)
                if "Failed to load image or audio file" not in message:
                    raise

        assert last_error is not None
        raise last_error

    caption = run_attempts(prompt)
    if training_focus != "style":
        return caption

    candidates = [caption]
    if style_caption_needs_retry(caption):
        retry_caption = run_attempts(build_style_retry_prompt(caption))
        candidates.append(retry_caption)
        if style_caption_needs_retry(retry_caption):
            second_retry_caption = run_attempts(build_style_retry_prompt_v2(retry_caption))
            candidates.append(second_retry_caption)

    return choose_best_style_caption(candidates)


def main() -> int:
    args = parse_args()
    dataset_dir = Path(args.dataset_dir)
    metadata_path = Path(args.metadata_path)

    if not dataset_dir.is_dir():
        print(f"Dataset folder does not exist: {dataset_dir}", file=sys.stderr)
        return 1

    rows = read_metadata(metadata_path, dataset_dir)
    if not rows:
        print("No supported images were found in the dataset folder.", file=sys.stderr)
        return 1

    model_id = load_model_id(args.endpoint)
    prompt = build_prompt(args.training_focus)

    drafted = 0
    skipped = 0

    for row in rows:
        current_text = row["prompt"].strip()
        if args.mode == "fill_blanks" and current_text:
            skipped += 1
            continue

        image_path = dataset_dir / row["image"]
        if not image_path.is_file():
            continue

        caption = request_caption(args.endpoint, model_id, prompt, image_path, args.training_focus)
        if not caption:
            raise RuntimeError(f"Caption Brain returned an empty caption for {row['image']}.")

        row["prompt"] = caption
        drafted += 1
        print(f"Drafted caption for {row['image']}: {caption}")

    write_metadata(metadata_path, rows)

    remaining_blank = sum(1 for row in rows if not row["prompt"].strip())
    print(
        f"Caption Brain wrote metadata.csv with {drafted} drafted caption(s), {skipped} skipped row(s), "
        f"and {remaining_blank} blank row(s) left."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

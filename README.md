# LoRA

LoRA is the NymphsCore training module for Z-Image Turbo LoRA workflows.

Under the hood it installs and manages an isolated AI Toolkit sidecar, but the module name is deliberately simple: `lora`.

It installs and manages:

- upstream `ostris/ai-toolkit`
- the official AI Toolkit Next.js UI on port `8675`
- the AI Toolkit Gradio UI on port `7861`
- queue worker support
- optional Z-Image Turbo training model cache, fetched after base install
- optional `ostris/zimage_turbo_training_adapter`, fetched after base install
- dataset, job, config, log, and LoRA output folders

This repo is intentionally a clean installer/contract repo. It is not a dump of a live `~/LoRA` runtime folder.

## Runtime Layout

Expected in-distro install path:

```text
~/LoRA
```

Generated runtime folders include:

```text
~/LoRA/ai-toolkit
~/LoRA/.node20
~/LoRA/datasets
~/LoRA/loras
~/LoRA/jobs
~/LoRA/logs
~/LoRA/config
~/LoRA/models
~/LoRA/adapters
~/LoRA/run
```

Those folders are local runtime state and must not be committed to this repo.

## Manager Contract

The manager discovers this module through `nymph.json`.

Useful scripts:

```bash
scripts/install_lora.sh
scripts/lora_status.sh
scripts/lora_start.sh
scripts/lora_stop.sh
scripts/lora_open.sh
scripts/lora_logs.sh
scripts/lora_fetch_assets.sh
scripts/lora_refresh.sh
```

The LoRA manager page is custom. `Easy LoRA` is the beginner workflow and keeps
the old Manager AI Toolkit handoff:

```text
captions / metadata.csv
-> Add Job
-> AI Toolkit job registration
-> Start Job
-> AI Toolkit queue start
-> progress/log polling
-> finished .safetensors output
```

`Add Job` creates or updates the AI Toolkit job. `Start Job` queues that saved
job and starts the AI Toolkit queue. `Stop Job` and `Delete Job` act only on AI
Toolkit jobs and do not delete datasets, captions, finished LoRAs, or downloaded
training assets.

The module `Logs` action should open the real module log file in Notepad via
`last_log=...`.

## Default Local URLs

```text
AI Toolkit official UI: http://localhost:8675
AI Toolkit Gradio UI:   http://localhost:7861
```

## Training Asset Pulls

Base install does not block on the large training weights. Use `scripts/lora_fetch_assets.sh` or the Manager `Prepare Training Assets` action to download or resume them.

The asset fetch pulls the Z-Image Turbo training bundle from:

```text
Tongyi-MAI/Z-Image-Turbo
```

The asset fetch pulls the Z-Image Turbo training adapter from:

```text
ostris/zimage_turbo_training_adapter
```

## Repo Rule

Keep this repo clean:

- keep installer scripts, wrapper scripts, docs, and `nymph.json`
- do not commit upstream `ai-toolkit` checkouts
- do not commit venvs or local Node runtimes
- do not commit datasets
- do not commit jobs
- do not commit generated LoRAs
- do not commit model bundles or adapter weights
- do not commit UI databases
- do not commit logs

## Current Source

The installer was copied from the working NymphsCore manager script:

```text
NymphsCore/Manager/scripts/install_zimage_trainer_aitk.sh
```

# LoRA

LoRA is the NymphsCore training module for Z-Image Turbo LoRA workflows.

Under the hood it installs and manages an isolated AI Toolkit sidecar, but the module name is deliberately simple: `lora`.

It installs and manages:

- upstream `ostris/ai-toolkit`
- the official AI Toolkit Next.js UI on port `8675`
- the AI Toolkit Gradio UI on port `7861`
- queue worker support
- Z-Image Turbo training model cache
- `ostris/zimage_turbo_training_adapter`
- dataset, job, config, log, and LoRA output folders

This repo is intentionally a clean installer/contract repo. It is not a dump of a live `~/ZImage-Trainer` runtime folder.

## Runtime Layout

Expected in-distro install path:

```text
~/ZImage-Trainer
```

Generated runtime folders include:

```text
~/ZImage-Trainer/ai-toolkit
~/ZImage-Trainer/.node20
~/ZImage-Trainer/datasets
~/ZImage-Trainer/loras
~/ZImage-Trainer/jobs
~/ZImage-Trainer/logs
~/ZImage-Trainer/config
~/ZImage-Trainer/models
~/ZImage-Trainer/adapters
~/ZImage-Trainer/run
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
scripts/lora_refresh.sh
```

The LoRA manager page should remain custom. It needs controls for datasets, jobs, generated LoRAs, UI launch, queue worker, and model/adaptor readiness.

## Default Local URLs

```text
AI Toolkit official UI: http://localhost:8675
AI Toolkit Gradio UI:   http://localhost:7861
```

## Model And Adapter Pulls

The installer pulls the Z-Image Turbo training bundle from:

```text
Tongyi-MAI/Z-Image-Turbo
```

The installer pulls the Z-Image Turbo training adapter from:

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

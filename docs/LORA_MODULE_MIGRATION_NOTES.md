# LoRA Module Migration Notes

The live install folder is:

```text
~/LoRA
```

That folder is a generated runtime, not the source repo.

It contains:

- upstream `ai-toolkit`
- Python virtual environments
- local Node runtime
- Prisma/UI database files
- Z-Image Turbo model bundle
- training adapter weights
- datasets
- jobs
- generated LoRAs
- logs

None of those should be copied into git.

## Module Identity

```text
id: lora
name: LoRA
short name: LO
repo: github.com/nymphnerds/lora
install path: ~/LoRA
```

## Source Of Truth

The clean module repo owns:

```text
scripts/install_lora.sh
scripts/lora_*.sh
```

The installer came from:

```text
NymphsCore/Manager/scripts/install_zimage_trainer_aitk.sh
```

## Underlying Backend

This module uses:

```text
https://github.com/ostris/ai-toolkit.git
```

but the Nymphs module name is `LoRA`, because that is the user-facing job.

## Custom Page Rule

The LoRA manager page must stay custom. It should expose:

- dataset folders
- training jobs
- generated LoRAs
- official AI Toolkit UI launch
- Gradio UI launch, if still useful
- queue worker status
- model and adapter readiness

The generic module facts page is only a fallback.

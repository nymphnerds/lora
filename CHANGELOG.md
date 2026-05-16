# LoRA Changelog

## 0.1.35 - 2026-05-16

- Validated Easy LoRA against the old Manager AI Toolkit flow with a tiny
  `my_first_lora` run in the managed `NymphsCore` WSL distro.
- Restored the old job handoff semantics:
  `Add Job` registers/updates the AI Toolkit train job, and `Start Job` now
  queues the job and starts the AI Toolkit GPU queue.
- Reworked Easy LoRA button states so the primary action follows the workflow:
  `Add Job` before a saved matching job exists, `Start Job` for an idle saved
  job, and `Stop Job` while queued/running.
- Renamed the manual status button to `Refresh` and made delete-job feedback
  return to the no-job state immediately.
- Matched old Manager defaults and labels more closely, including rank order,
  learning-rate options, `Add Job` / `Start Job`, folder buttons, LoRA/dataset
  counts, and preset defaults.
- Added hover help/tooltips for beginner controls.
- Improved Caption with Brain feedback in the live log and kept the old
  style-safe captioning focus.
- Fixed progress parsing so warmup lines like checkpoint-shard loading do not
  show as 100% training progress.
- Fixed completed-job display to show the final total steps when the final
  `.safetensors` exists.
- Fixed LoRA counting so intermediate checkpoint files do not count as separate
  finished LoRAs.
- Updated the module `Logs` action to open the real module log file in Notepad.


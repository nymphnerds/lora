# Easy LoRA Module Handoff

Date: 2026-05-15

## Goal

Port the old main-branch Z-Image Trainer into the modular `LoRA` module.

The module is named:

```text
LoRA
```

The beginner UI is named:

```text
Easy LoRA
```

The advanced official UI keeps its existing name:

```text
AI Toolkit
```

## Important Rule

Use `NymphsCore` `main` as the reference implementation.

The old Manager trainer took days to get right. This is the most complex module in the first module set and should be ported closely, not reimagined.

Every implementation pass should keep the old `NymphsCore` `main` Manager code open as the behavioral reference. Treat the old code as the parity target for workflow, edge cases, defaults, API calls, progress parsing, caption behavior, and recovery behavior.

Do not make a LoRA module change from memory if the old Manager already implemented that part. Check the old files first, then port the behavior into module-owned scripts/UI/actions.

When simplifying, only simplify after deliberately confirming one of these is true:

- the old behavior was Manager-shell-specific and no longer belongs in the module
- the new module standard replaces the old mechanism without changing user-visible behavior
- a fallback is being added while preserving the AI Toolkit job flow as the product path
- the change is explicitly documented as a deliberate behavior change

Do not treat this as a simple UI wrapper or shell script launcher. The old implementation coordinates:

- local Brain LLM captioning
- dataset folder and `metadata.csv` management
- preserving and filling captions
- converting CSV captions into individual sidecar `.txt` files
- AI Toolkit install/bootstrap
- AI Toolkit API settings
- AI Toolkit job registration/upsert
- AI Toolkit queue start/stop/delete/log polling
- progress parsing from toolkit logs
- model and adapter readiness checks

Do not replace its AI Toolkit job flow with a simpler direct-run flow unless deliberately adding a fallback.

Source of truth references:

```text
NymphsCore origin/main:
Manager/apps/NymphsCoreManager/Views/MainWindow.xaml
Manager/apps/NymphsCoreManager/ViewModels/MainWindowViewModel.cs
Manager/apps/NymphsCoreManager/Services/InstallerWorkflowService.cs
Manager/apps/NymphsCoreManager/Models/ZImageTrainerStatus.cs
Manager/scripts/install_zimage_trainer_aitk.sh
Manager/scripts/zimage_trainer_status.sh
Manager/scripts/zimage_caption_brain.sh
Manager/scripts/zimage_caption_brain.py
Manager/scripts/ztrain_run_config.sh
```

Current module repo:

```text
NymphsModules/lora
```

## Current State Snapshot

This section reflects the local modular build after the 2026-05-15 install and
asset-fetch testing.

The module is installable and visible in the standard Manager module shell.
It is not yet a working Easy LoRA trainer workflow.

### Done

- `LoRA` exists as a first-party module repo with manifest version `0.1.11`.
- The Manager can install, update, repair, uninstall, and delete LoRA data using
  the standard module lifecycle rail.
- Base install creates the isolated trainer root:

```text
/home/nymph/ZImage-Trainer
```

- Base install prepares the AI Toolkit checkout, Python venv, local Node 20,
  official AI Toolkit UI dependencies/build, Prisma DB, launcher scripts,
  module scripts, and module UI files.
- Base install no longer downloads the huge training weights.
- `Fetch Training Assets` is a separate explicit action and now reports useful
  progress while downloading/resuming:

```text
Tongyi-MAI/Z-Image-Turbo
ostris/zimage_turbo_training_adapter
```

- LoRA status reports `assets_ready=true` when the model bundle, adapter, and
  `.training-assets-ready` marker are all present.
- The Manager details pane only shows the `Fetch Training Assets` next-step
  prompt while the module state is actually `Needs assets`.
- `Easy LoRA` opens `ui/manager.html` inside Manager WebView2.
- `AI Toolkit`, `Open Datasets`, `Open LoRAs`, and `Logs` actions are exposed
  as module actions.
- `Delete Data` is separate from uninstall and is available through the
  universal rail.

### Partially Done

- `ui/manager.html` is the intended compact Easy LoRA surface, but it is mostly
  static HTML right now.
- The Easy LoRA page visually contains the right controls, but the controls do
  not yet create jobs, start/stop training, delete jobs, caption with Brain, or
  poll live AI Toolkit state.
- The Manager has a basic local HTML action hook:

```text
nymphs-module-action://<action>?key=value
```

It can run installed module entrypoints declared in `nymph.json`, but current
behavior sends the user to the Manager Logs page and only updates
`ModuleUiStatus`. It is useful for simple one-shot actions, but not sufficient
by itself for the polished in-place Easy LoRA workflow shown in the HTML.
- The old main-branch AI Toolkit job flow still exists in `NymphsCore`
  Manager code and should be ported, not rewritten from memory.

### Not Done

The following are not module-owned yet:

- dataset metadata refresh from the Easy LoRA UI
- `Open Pictures` for the selected LoRA/dataset
- `Open Captions` for the selected `metadata.csv`
- `Caption with Brain`
- sidecar `.txt` caption mirroring
- AI Toolkit job YAML generation from Easy LoRA form values
- AI Toolkit JSON `job_config` generation from Easy LoRA form values
- AI Toolkit job upsert/register through `/api/jobs`
- current job lookup/import into the Easy LoRA UI
- Start Training through the AI Toolkit queue
- Stop Job through AI Toolkit job stop/mark-stopped endpoints
- Delete Job through AI Toolkit job delete endpoint
- live job log polling
- real progress parsing inside Easy LoRA
- final checkpoint detection
- finished LoRA discovery/summary in the Easy LoRA page

### Current User-Visible Reality

When `Easy LoRA` opens today, it is a front-end shell. The displayed progress
bar and log text are placeholder/mock state:

```text
Training progress 18%
Easy LoRA status check completed.
No job created yet.
```

Do not treat this as wired behavior.

### Current Module Actions

Declared in `nymph.json`:

```text
easy_lora      -> opens module UI
fetch_assets   -> downloads/resumes training assets
aitoolkit      -> starts/opens official AI Toolkit
open_datasets  -> opens /home/nymph/ZImage-Trainer/datasets
open_loras     -> opens /home/nymph/ZImage-Trainer/loras
logs           -> tails LoRA/AI Toolkit logs
```

Not yet declared or implemented:

```text
open_pictures
open_captions
caption_brain
create_job
start_job
stop_job
delete_job
job_status
```

## Current Architecture Decision

The Manager should not regain a hardcoded LoRA page.

The Manager owns:

- module shell
- sidebar
- module details pane
- install/update/uninstall rail
- logs page
- generic action routing
- WebView2 hosting

The LoRA module owns:

- installer
- status/start/stop/open/logs actions
- Easy LoRA UI
- AI Toolkit launch action
- dataset/caption/job helpers
- AI Toolkit API integration

## UI Shape

The module detail page should show module-level facts only. Do not duplicate the full Easy LoRA form there.

Suggested details pane:

```text
LoRA
Local LoRA training module powered by AI Toolkit.

Status
Installed: yes/no
Trainer: ready/missing
LoRAs: N
Datasets: N
AI Toolkit: running/stopped
Training backend: Z-Image Turbo initially, future runtimes later
Model files: ready/missing
Adapter: ready/missing

Folders
Datasets
LoRAs
Jobs
Logs
```

Module actions should include:

```text
Easy LoRA
AI Toolkit
Open LoRAs
Open Datasets
Logs
```

`Easy LoRA` opens the module-owned beginner HTML UI.

`AI Toolkit` opens the official AI Toolkit UI. It may open in Manager WebView2 or external browser depending on current Manager support/action result.

Gradio can remain as a dev/hidden script if useful, but it should not be part of the beginner Easy LoRA surface.

## Easy LoRA UI

Easy LoRA should be compact. It should not recreate the whole Manager page.

Manager-owned module state should not be repeated inside the HTML. Keep install state, LoRA/dataset counts, queue/backend health, AI Toolkit launch, and module folder shortcuts in the Manager details/actions area.

It should contain only the trainer controls:

```text
LoRA name
Open Pictures
Caption with Brain
Caption fill mode
Open Captions
Preset
Training adapter
Sample prompt
Steps
Checkpoints
Learning rate
LoRA rank
Low VRAM mode
Create Job
Start Training
Stop Job
Delete Job
Progress
Live log / status
```

The progress bar belongs in the Easy LoRA HTML because it is current-job workflow state.

Because this will likely run inside Manager WebView2, the HTML must handle narrow embedded widths gracefully:

- desktop/wide: compact multi-column form
- medium WebView widths: label + content rows, action buttons wrap under fields
- narrow widths: single-column controls
- job buttons should become two-column, then one-column
- button text should wrap instead of forcing horizontal overflow

Use the old screenshot/layout as the workflow reference, but polish the styling.

![Old Easy LoRA UI from main manager](assets/easy-lora-old-manager-ui.png)

Labels agreed in discussion:

```text
Module: LoRA
Easy UI/button: Easy LoRA
Advanced UI/button: AI Toolkit
```

Avoid:

```text
Nymph Trainer
Nymphs Trainer
Z-Image Trainer as the module/page title
```

## Easy LoRA Wiring Decision

The current Manager can intercept this URL scheme from local module HTML:

```text
nymphs-module-action://create_job?lora=my_first_lora
```

The action name must be present in the module capabilities, which currently
come from `entrypoints` in `nymph.json`.

Current limits:

- query args become CLI flags, for example `?lora=my_first_lora` becomes
  `--lora my_first_lora`
- argument values are intentionally restricted to short safe strings
- the Manager currently changes to the Logs page while the action runs
- the HTML does not receive a structured response payload

This is enough for smoke-test buttons and simple actions. It is not enough for
the final Easy LoRA experience unless the UX accepts leaving the page during
each action.

Recommended approach for the real trainer UI:

1. Add a module-owned lightweight local helper API for Easy LoRA, or extend the
   Manager module-UI bridge to support structured request/response without
   leaving the WebView.
2. Keep all LoRA/AI Toolkit logic module-owned.
3. Let the HTML poll `job_status` and `job_log` frequently while a job exists.
4. Use the existing Manager action scheme only as a fallback for one-shot
   actions until a better bridge exists.

## The Critical Job Flow

Easy LoRA must send jobs to AI Toolkit the way `main` does.

Required behavior:

```text
Easy LoRA form values
-> normalize LoRA/dataset name
-> prepare dataset metadata.csv
-> mirror metadata.csv captions to per-image .txt files
-> ensure selected training adapter exists
-> generate AI Toolkit YAML job
-> generate AI Toolkit JSON job_config
-> upsert/register job through AI Toolkit API
-> job appears in AI Toolkit Jobs
-> Start Training queues/starts the AI Toolkit job
```

Do not reduce this to only:

```text
python run.py jobs/name.yaml
```

That direct runner exists in the old script and may be useful as fallback, but the product flow is AI Toolkit registration and queue control.

## Main-Branch Port Map

The old working behavior is concentrated in these Manager methods. These are
the practical port checklist.

From `Manager/apps/NymphsCoreManager/ViewModels/MainWindowViewModel.cs`:

```text
RefreshZImageTrainerStatusAsync
RefreshZImageTrainerLiveStateAsync
CreateZImageTrainerJobAsync
OpenZImageTrainerPicturesFolderAsync
OpenZImageTrainerCaptionsFileAsync
DraftZImageTrainerCaptionsAsync
StartZImageTrainingAsync
StartZImageTrainerQueueAsync
StopZImageTrainerQueueAsync
DeleteZImageTrainerJobAsync
ViewZImageTrainerJobAsync
LaunchZImageTrainerOfficialUiAsync
KillZImageTrainerOfficialUiAsync
TryImportZImageTrainerJobSettingsAsync
ApplyZImageTrainerPresetDefaults
UpdateZImageTrainerProgressFromLine
```

From `Manager/apps/NymphsCoreManager/Services/InstallerWorkflowService.cs`:

```text
GetZImageTrainerStatusAsync
GetZImageTrainerDatasetNamesAsync
GetZImageTrainerJobSettingsAsync
CreateZImageTrainerJobAsync
RunZImageTrainerJobAsync
StartZImageTrainerQueueAsync
StopZImageTrainerQueueAsync
DeleteZImageTrainerJobAsync
GetZImageTrainerJobIdAsync
TryGetZImageTrainerJobLogAsync
StopZImageTrainerJobAsync
EnsureZImageTrainerPicturesFolderAsync
PrepareZImageTrainerMetadataAsync
EnsureZImageTrainerTrainingAdapterAsync
DraftZImageTrainerCaptionsAsync
BuildZImageTrainerConfig
BuildZImageTrainerConfigJson
BuildZImageLoraMetadataJson
TryRegisterZImageTrainerJobInOfficialUiAsync
FindOfficialUiJobIdAsync
QueueOfficialUiJobAsync
EnsureAiToolkitApiReadyAsync
EnsureAiToolkitSettingsConfiguredAsync
EnrichZImageTrainerStatusFromAiToolkitAsync
TryGetAiToolkitDatasetVisibilityAsync
UpsertAiToolkitJobViaApiAsync
TryGetAiToolkitJobByRefAsync
GetAiToolkitActiveTrainJobAsync
WaitForAiToolkitJobLiveStateAsync
SendAiToolkitApiRequestAsync
ReadTrainerMetadata
WriteTrainerMetadata
SyncTrainerCaptionTextFiles
```

The port should move this behavior into module-owned helpers, probably:

```text
scripts/lora_job.py
scripts/lora_caption_brain.sh
scripts/lora_caption_brain.py
scripts/lora_create_job.sh
scripts/lora_start_job.sh
scripts/lora_stop_job.sh
scripts/lora_delete_job.sh
scripts/lora_job_status.sh
scripts/lora_open_pictures.sh
scripts/lora_open_captions.sh
```

Keep the C# code open during implementation and port behavior in small slices.

## AI Toolkit API Endpoints From Main

The old Manager talks to AI Toolkit on:

```text
http://127.0.0.1:8675
```

Important endpoints:

```text
GET  /api/settings
POST /api/settings
GET  /api/jobs?job_ref=<name>
GET  /api/jobs?id=<id>
GET  /api/jobs?job_type=train
POST /api/jobs
GET  /api/jobs/<id>/start
GET  /api/jobs/<id>/stop
GET  /api/jobs/<id>/mark_stopped
GET  /api/jobs/<id>/delete
GET  /api/jobs/<id>/log
GET  /api/queue
GET  /api/queue/<gpu_ids>/start
GET  /api/queue/<gpu_ids>/stop
GET  /api/datasets/list
POST /api/datasets/listImages
```

The module should move this API glue into module-owned scripts/helpers, likely Python for JSON/HTTP handling.

## Dataset And Captions

Preserve main behavior:

- dataset folder is based on normalized LoRA name
- `metadata.csv` is the user-editable caption source
- supported image types:

```text
.png
.jpg
.jpeg
.webp
.bmp
```

- refreshing metadata keeps existing captions
- new image files get blank captions
- removed images disappear from metadata
- creating/updating a job mirrors `metadata.csv` captions to sidecar `.txt` files for AI Toolkit

User-facing language:

```text
Open Captions
```

is preferred over:

```text
Open Draft CSV
```

unless the old technical wording is intentionally kept.

## Caption With Brain

Preserve main behavior.

The old flow:

- finds or starts a compatible Brain vision model
- temporarily switches Brain to a vision model if needed
- sends normalized JPEG previews to Brain
- writes one caption per image into `metadata.csv`
- supports:

```text
fill_blanks
overwrite_all
```

- has special style-caption cleanup/retry logic

Important files:

```text
Manager/scripts/zimage_caption_brain.sh
Manager/scripts/zimage_caption_brain.py
```

These should be copied/migrated into the LoRA module, not kept as Manager-owned scripts.

## Presets And Controls

Main currently supports:

```text
Fast Test
Baseline
Style
Strong Style
```

Recent/docs language also mentions:

```text
Baseline
Style
Style High Noise
```

Resolve labels carefully during implementation. The old main behavior wins unless intentionally renamed.

Core defaults from main:

```text
baseline:
  steps: 3000
  checkpoints: 4
  learning_rate: 1e-4
  rank: 16
  resolution: 1024
  content_or_style: balanced

style:
  steps: 3000
  checkpoints: 4
  learning_rate: 1e-4
  rank: 16
  resolution: 1024
  content_or_style: balanced

strong_style:
  steps: 5000
  checkpoints: 4
  learning_rate: 1e-4
  rank: 16
  resolution: 1024
  content_or_style: content

fast_test:
  steps: 500
  checkpoints: 0
  learning_rate: 1e-4
  rank: 8
  resolution: 512
```

Training adapter:

```text
v1 (Recommended)
v2 (Experimental)
```

## Install Responsibilities

The module installer should continue to prepare:

- AI Toolkit checkout
- Python venv
- Torch/dependencies
- local Node 20
- official AI Toolkit UI deps/build
- Prisma DB
- launcher scripts
- helper scripts
- module manifest/UI files in the install root
- `.nymph-module-version` written last

Large training assets are intentionally a second explicit step:

- `scripts/lora_fetch_assets.sh`
- Manager action label: `Prepare Training Assets`
- downloads/resumes Z-Image Turbo model cache
- downloads/resumes `ostris/zimage_turbo_training_adapter`
- selects/writes `selected_adapter_path.txt`

This keeps base install from looking hung while multi-GB Hugging Face weights download.

Asset reality:

- Z-Image Turbo LoRA training still needs the full
  `Tongyi-MAI/Z-Image-Turbo` training bundle.
- Unlike Z-Image/TRELLIS inference modules, this is not currently a clean
  `int4_r32` / `Q5_K_M` style weight dropdown.
- The adapter repo contains separate adapter files, currently observed as:

```text
zimage_turbo_training_adapter_v1.safetensors
zimage_turbo_training_adapter_v2.safetensors
```

- The UI should expose adapter selection for training jobs.
- A future `Fetch Training Assets` selector could download `v1`, `v2`, or both,
  but the base Z-Image Turbo model bundle remains required for training.

Install root:

```text
/home/nymph/ZImage-Trainer
```

Preserve user data on repair/uninstall unless purging:

```text
datasets
loras
jobs
config
logs
```

## Status Responsibilities

Status should be fast and key/value based.

It should report at least:

```text
id=lora
installed=true/false
runtime_present=true/false
data_present=true/false
version=<version>
repo_ready=true/false
venv_ready=true/false
node_ready=true/false
ui_ready=true/false
adapter_ready=true/false
model_ready=true/false
official_ui_running=true/false
queue_worker_running=true/false
queue_running=true/false
active_state=idle/queued/running/...
active_info=<text>
lora_count=N
dataset_count=N
running=true/false
state=available/installed/needs_assets/running/needs_attention
health=ok/degraded/missing
install_root=/home/nymph/ZImage-Trainer
datasets=/home/nymph/ZImage-Trainer/datasets
loras=/home/nymph/ZImage-Trainer/loras
jobs=/home/nymph/ZImage-Trainer/jobs
logs_dir=/home/nymph/ZImage-Trainer/logs
marker=/home/nymph/ZImage-Trainer/.nymph-module-version
detail=<human summary>
```

It should not run heavy model scans at Manager startup.

## Progress

Preserve the main progress behavior:

- parse `TRAIN_PROGRESS current=x total=y`
- parse common AI Toolkit warmup log lines
- detect final checkpoint save
- check final `.safetensors`
- poll AI Toolkit job log when available

This can be implemented in the Easy LoRA HTML plus module helper endpoint/action output, or in module scripts that print structured progress.

## Open Questions

1. Whether Easy LoRA should use a module-owned local helper API or a richer
   Manager WebView2 bridge for in-page structured actions.
2. Whether AI Toolkit should open inside Manager WebView2 by default or external
   browser by default.
3. Whether to expose Gradio as a hidden/dev action.
4. Whether preset labels should stay `Strong Style` or become `Style High Noise`.
5. Whether LoRA should download both adapter weights by default forever, or
   expose an adapter/weight selector during `Fetch Training Assets`.
6. How generic to make future training targets beyond Z-Image Turbo.

## Recommended Implementation Order

Completed already:

```text
install/update/status/uninstall wrappers
separate training asset fetch
standard lifecycle rail support
Easy LoRA local HTML surface
AI Toolkit/Open Datasets/Open LoRAs/Logs module actions
```

Next implementation pass:

1. Add module-owned helpers copied/ported from `NymphsCore origin/main`.
2. Start with dataset/caption file operations that do not require AI Toolkit:

```text
open_pictures
open_captions
prepare_metadata
sync_caption_txt
```

3. Add `job_status` that reports real state for one selected LoRA name:

```text
dataset exists/missing
metadata exists/missing
image_count
missing_caption_count
selected AI Toolkit job id/state/info
latest log tail
progress current/total/percent
final checkpoint exists
```

4. Add module-owned Python helper for AI Toolkit API/job operations.
5. Add job lifecycle module actions:

```text
create_job
start_job
stop_job
delete_job
```

6. Add Brain caption helpers and wire `Caption with Brain`.
7. Decide and implement the Easy LoRA HTML communication path:

```text
module-owned local helper API
or richer Manager WebView2 bridge
```

8. Wire `ui/manager.html` to real status/actions.
9. Test full AI Toolkit job roundtrip with a tiny dataset.
10. Only after that, polish UI styling.

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

PURGE=0
DATA_ONLY=0
DRY_RUN=0
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --data-only) DATA_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: lora_uninstall.sh [--dry-run] [--yes] [--purge] [--data-only]

Default uninstall removes AI Toolkit/runtime pieces but preserves datasets,
jobs, generated LoRAs, config, logs, and downloaded training assets.
--purge removes the whole trainer root, including datasets and generated LoRAs.
--data-only deletes datasets, generated LoRAs, jobs, config, logs, models, and adapters while keeping the runtime.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${PURGE}" -eq 1 && "${DATA_ONLY}" -eq 1 ]]; then
  echo "Choose only one of --purge or --data-only." >&2
  exit 2
fi

echo "LoRA uninstall plan"
echo "install_root=${LORA_INSTALL_ROOT}"
if [[ "${DATA_ONLY}" -eq 1 ]]; then
  echo "mode=data-only"
  echo "delete=${LORA_INSTALL_ROOT}/datasets"
  echo "delete=${LORA_INSTALL_ROOT}/loras"
  echo "delete=${LORA_INSTALL_ROOT}/jobs"
  echo "delete=${LORA_INSTALL_ROOT}/config"
  echo "delete=${LORA_INSTALL_ROOT}/logs"
  echo "delete=${LORA_INSTALL_ROOT}/models"
  echo "delete=${LORA_INSTALL_ROOT}/adapters"
  echo "preserve=${LORA_INSTALL_ROOT}/ai-toolkit"
  echo "preserve=${LORA_INSTALL_ROOT}/.node20"
  echo "preserve=${LORA_INSTALL_ROOT}/bin"
elif [[ "${PURGE}" -eq 1 ]]; then
  echo "mode=purge"
  echo "delete=${LORA_INSTALL_ROOT}"
else
  echo "mode=uninstall"
  echo "delete=${LORA_INSTALL_ROOT}/ai-toolkit"
  echo "delete=${LORA_INSTALL_ROOT}/.node20"
  echo "delete=${LORA_INSTALL_ROOT}/run"
  echo "delete=${LORA_INSTALL_ROOT}/bin"
  echo "preserve=${LORA_INSTALL_ROOT}/datasets"
  echo "preserve=${LORA_INSTALL_ROOT}/loras"
  echo "preserve=${LORA_INSTALL_ROOT}/jobs"
  echo "preserve=${LORA_INSTALL_ROOT}/config"
  echo "preserve=${LORA_INSTALL_ROOT}/logs"
  echo "preserve=${LORA_INSTALL_ROOT}/models"
  echo "preserve=${LORA_INSTALL_ROOT}/adapters"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  exit 0
fi

if [[ "${YES}" -ne 1 ]]; then
  echo "Refusing to delete without --yes. Run with --dry-run first to preview." >&2
  exit 2
fi

"${SCRIPT_DIR}/lora_stop.sh" || true

if [[ ! -d "${LORA_INSTALL_ROOT}" ]]; then
  echo "LoRA trainer is already uninstalled."
  exit 0
fi

if [[ "${DATA_ONLY}" -eq 1 ]]; then
  rm -rf \
    "${LORA_INSTALL_ROOT}/datasets" \
    "${LORA_INSTALL_ROOT}/loras" \
    "${LORA_INSTALL_ROOT}/jobs" \
    "${LORA_INSTALL_ROOT}/config" \
    "${LORA_INSTALL_ROOT}/logs" \
    "${LORA_INSTALL_ROOT}/models" \
    "${LORA_INSTALL_ROOT}/adapters"
elif [[ "${PURGE}" -eq 1 ]]; then
  rm -rf "${LORA_INSTALL_ROOT}"
else
  rm -f "${LORA_INSTALL_ROOT}/.nymph-module-version"
  rm -rf \
    "${LORA_INSTALL_ROOT}/ai-toolkit" \
    "${LORA_INSTALL_ROOT}/.node20" \
    "${LORA_INSTALL_ROOT}/run" \
    "${LORA_INSTALL_ROOT}/bin"
fi

if [[ "${DATA_ONLY}" -eq 1 ]]; then
  echo "LoRA trainer data deleted."
else
  echo "LoRA trainer uninstalled."
fi

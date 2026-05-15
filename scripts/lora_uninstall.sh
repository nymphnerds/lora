#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

PURGE=0
DRY_RUN=0
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: lora_uninstall.sh [--dry-run] [--yes] [--purge]

Default uninstall removes AI Toolkit/runtime pieces but preserves datasets,
jobs, generated LoRAs, config, logs, and downloaded training assets.
--purge removes the whole trainer root, including datasets and generated LoRAs.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

echo "LoRA uninstall plan"
echo "install_root=${LORA_INSTALL_ROOT}"
if [[ "${PURGE}" -eq 1 ]]; then
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

if [[ "${PURGE}" -eq 1 ]]; then
  rm -rf "${LORA_INSTALL_ROOT}"
else
  rm -f "${LORA_INSTALL_ROOT}/.nymph-module-version"
  rm -rf \
    "${LORA_INSTALL_ROOT}/ai-toolkit" \
    "${LORA_INSTALL_ROOT}/.node20" \
    "${LORA_INSTALL_ROOT}/run" \
    "${LORA_INSTALL_ROOT}/bin"
fi

echo "LoRA trainer uninstalled."

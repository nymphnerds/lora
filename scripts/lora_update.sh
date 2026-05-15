#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

if [[ ! -f "${LORA_INSTALL_ROOT}/.nymph-module-version" ]]; then
  echo "LoRA is not installed yet. Use Install first." >&2
  exit 2
fi

mkdir -p "${LORA_INSTALL_ROOT}/scripts"
install -m 644 "${MODULE_ROOT}/nymph.json" "${LORA_INSTALL_ROOT}/nymph.json"
install -m 755 "${MODULE_ROOT}"/scripts/*.sh "${LORA_INSTALL_ROOT}/scripts/"

module_version="$(python3 - "${MODULE_ROOT}/nymph.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

print(str(manifest.get("version", "unknown")).strip() or "unknown")
PY
)"
printf '%s\n' "${module_version}" > "${LORA_INSTALL_ROOT}/.nymph-module-version"

echo "LoRA module wrappers updated."
echo "installed_version=${module_version}"

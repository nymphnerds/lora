#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lora_common.sh"

mkdir -p "${LORA_JOB_DIR}"
echo "directory=${LORA_JOB_DIR}"

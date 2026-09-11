#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_tools
demo_dir="$(mktemp -d)"
trap 'rm -rf -- "$demo_dir"' EXIT
export KOF_DATABASE="$demo_dir/jobs.db"
KOF_ACTION=enqueue bash "$ROOT_DIR/scripts/example.sh"
KOF_ACTION=work bash "$ROOT_DIR/scripts/example.sh"

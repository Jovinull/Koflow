#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_tools
cd "$ROOT_DIR"
compile . build/classes
test -f build/classes/koflow/JobStore.class

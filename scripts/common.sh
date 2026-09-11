#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/koflow"
KOF="${KOF:-$TOOL_CACHE/kof-0.3.22-beta-linux-x86_64/bin/kof}"
JAVA="${JAVA:-$TOOL_CACHE/kof-0.3.22-beta-linux-x86_64/jdk/bin/java}"
SQLITE_JDBC="${SQLITE_JDBC:-$TOOL_CACHE/sqlite-jdbc-3.53.4.0.jar}"

require_tools() {
    if [[ ! -x "$KOF" || ! -x "$JAVA" || ! -f "$SQLITE_JDBC" ]]; then
        echo 'Dependências ausentes. Execute make bootstrap ou configure KOF, JAVA e SQLITE_JDBC.' >&2
        exit 1
    fi
}

compile() {
    local source_dir="$1" output_dir="$2"
    "$KOF" build "$source_dir" --target jvm --output "$output_dir"
}

run_class() {
    local output_dir="$1" class_name="$2"
    shift 2
    "$JAVA" -cp "$output_dir:$SQLITE_JDBC" "$class_name" "$@"
}

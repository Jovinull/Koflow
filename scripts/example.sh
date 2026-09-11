#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_tools
example_dir="$(mktemp -d)"
trap 'rm -rf -- "$example_dir"' EXIT
mkdir -p "$example_dir/source"
cp -R "$ROOT_DIR/koflow" "$example_dir/source/"
cp "$ROOT_DIR/examples/basic/Main.kf" "$example_dir/source/"
compile "$example_dir/source" "$example_dir/classes"
test -f "$example_dir/classes/Default/Main.class"
run_class "$example_dir/classes" Default.Main

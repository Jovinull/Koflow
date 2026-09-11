#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo 'O bootstrap suporta Linux x86_64. Configure KOF, JAVA e SQLITE_JDBC para outro ambiente.' >&2
    exit 1
fi

mkdir -p "$TOOL_CACHE"
install_dir="$(mktemp -d "$TOOL_CACHE/download.XXXXXX")"
trap 'rm -rf -- "$install_dir"' EXIT

if [[ ! -x "$KOF" ]]; then
    curl -fL --retry 3 --retry-all-errors \
        'https://github.com/KofLang/Kof4j/releases/download/kof-0.3.22-beta-linux-x86_64/kof-0.3.22-beta-linux-x86_64.tar.gz' \
        -o "$install_dir/kof.tar.gz"
    printf '%s  %s\n' a2bc9f85a406eeb61282795cb2ad131668eb5b711c66fbea446fc40b234116f4 "$install_dir/kof.tar.gz" | sha256sum -c -
    tar -xzf "$install_dir/kof.tar.gz" -C "$install_dir"
    if [[ -e "$TOOL_CACHE/kof-0.3.22-beta-linux-x86_64" ]]; then
        echo 'Distribuição incompleta já existe no cache; selecione outro XDG_CACHE_HOME.' >&2
        exit 1
    fi
    mv "$install_dir/kof-0.3.22-beta-linux-x86_64" "$TOOL_CACHE/"
fi

if [[ ! -f "$SQLITE_JDBC" ]]; then
    curl -fL --retry 3 --retry-all-errors \
        'https://repo.maven.apache.org/maven2/org/xerial/sqlite-jdbc/3.53.4.0/sqlite-jdbc-3.53.4.0.jar' \
        -o "$install_dir/sqlite-jdbc-3.53.4.0.jar"
    printf '%s  %s\n' bcb1f51e36f940867e83342f9efbf5968ac44a6bef4d397bb4af7b17b45cd2fb "$install_dir/sqlite-jdbc-3.53.4.0.jar" | sha256sum -c -
    mv "$install_dir/sqlite-jdbc-3.53.4.0.jar" "$TOOL_CACHE/"
fi

require_tools
"$KOF" version

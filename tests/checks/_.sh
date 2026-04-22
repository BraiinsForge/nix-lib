#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel)
SYSTEM=$(nix eval --impure --raw --expr builtins.currentSystem)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

build_checker() {
    local exclude_glob=${1:-}
    local expr

    if [[ -n $exclude_glob ]]; then
        expr=$(
            cat <<EOF
let
  flake = builtins.getFlake "${REPO_ROOT}";
in
  flake.braiinschk."${SYSTEM}" {
    mermaid = true;
    justfile = true;
    shell = true;
    config.exclude = [ "${exclude_glob}" ];
  }
EOF
        )
    else
        expr=$(
            cat <<EOF
let
  flake = builtins.getFlake "${REPO_ROOT}";
in
  flake.braiinschk."${SYSTEM}" {
    mermaid = true;
    justfile = true;
    shell = true;
  }
EOF
        )
    fi

    nix build --impure --no-link --print-out-paths --expr "$expr"
}

copy_case_repo() {
    local case_name=$1
    local repo_dir="$TEMP_DIR/$case_name"
    mkdir -p "$repo_dir"
    cp -R "$SCRIPT_DIR/$case_name"/. "$repo_dir"/
    git -C "$repo_dir" init -q
    git -C "$repo_dir" add .
    printf '%s\n' "$repo_dir"
}

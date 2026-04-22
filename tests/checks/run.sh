#!/usr/bin/env bash
set -euo pipefail

GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

echo "=== Checker Validation Tests ==="

# shellcheck source-path=SCRIPTDIR
# shellcheck source=_.sh
source "$(dirname "${BASH_SOURCE[0]}")/_.sh"

run_case() {
    local case_name=$1
    local expected=$2
    local checker=$3
    local repo
    local stdout_file="$TEMP_DIR/$case_name.stdout"
    local stderr_file="$TEMP_DIR/$case_name.stderr"

    repo=$(copy_case_repo "$case_name")

    echo ""
    echo "--- $case_name ---"
    if (cd "$repo" && "$checker/bin/braiinschk" >"$stdout_file" 2>"$stderr_file"); then
        status=0
    else
        status=$?
    fi

    cat "$stdout_file"
    cat "$stderr_file" >&2

    if [[ $expected == pass && $status -ne 0 ]]; then
        echo "${RED}FAIL${RESET}: $case_name (expected pass, got failure)" >&2
        exit 1
    fi

    if [[ $expected == fail && $status -eq 0 ]]; then
        echo "${RED}FAIL${RESET}: $case_name (expected failure, got success)" >&2
        exit 1
    fi

    if [[ $expected == fail ]]; then
        echo "${YELLOW}EXPECTED FAIL${RESET}: $case_name"
        return
    fi

    echo "${GREEN}PASS${RESET}: $case_name"
}

DEFAULT_CHECKER=$(build_checker)
EXCLUDED_CHECKER=$(build_checker "excluded/**")

run_case "pass-shell" pass "$DEFAULT_CHECKER"
run_case "fail-shell" fail "$DEFAULT_CHECKER"
run_case "excluded-shell" pass "$EXCLUDED_CHECKER"
run_case "content-composition" pass "$DEFAULT_CHECKER"
run_case "ignored-extension" pass "$DEFAULT_CHECKER"

echo ""
echo "All checker tests passed!"

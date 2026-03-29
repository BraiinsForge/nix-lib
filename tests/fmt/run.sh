#!/usr/bin/env bash
set -euo pipefail

GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

echo "=== Formatter Snapshot Tests ==="

# shellcheck source=_.sh
source "$(dirname "${BASH_SOURCE[0]}")/_.sh"

# Compare with expected output
echo "Comparing results..."
FAILED=0
for clean_file in "$SCRIPT_DIR/clean/"*; do
    filename=$(basename "$clean_file")
    temp_file="$TEMP_DIR/$filename"

    if [[ ! -f $temp_file ]]; then
        echo "${YELLOW}SKIP${RESET}: $filename (not in dirty/)"
        continue
    fi

    if diff -q "$clean_file" "$temp_file" >/dev/null 2>&1; then
        echo "${GREEN}PASS${RESET}: $filename"
    else
        echo "${RED}FAIL${RESET}: $filename"
        echo "  Expected:"
        head -5 "$clean_file" | sed 's/^/    /'
        echo "  Got:"
        head -5 "$temp_file" | sed 's/^/    /'
        FAILED=1
    fi
done

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo "${GREEN}All tests passed!${RESET}"
    exit 0
else
    echo ""
    echo "${RED}Some tests failed!${RESET}"
    echo "Run update.sh to regenerate snapshots"
    exit 1
fi

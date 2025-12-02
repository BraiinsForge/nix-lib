#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_MODE=false

if [[ "${1:-}" == "--update" ]]; then
    UPDATE_MODE=true
    echo "=== Updating Formatter Snapshots ==="
else
    echo "=== Formatter Snapshot Tests ==="
fi

# Create temp directory for test output
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
echo "Temp dir: $TEMP_DIR"

# Copy dirty files to temp
cp "$SCRIPT_DIR/dirty/"* "$TEMP_DIR/"

# Build and run formatter with all options enabled
echo "Building formatter..."
nix build --impure --expr "(builtins.getFlake \"$REPO_ROOT\").braiinsfmt.$(nix eval --impure --raw --expr 'builtins.currentSystem') { javascript = true; typescript = true; css = true; html = true; graphql = true; markdown = true; }" -o "$TEMP_DIR/fmt"

echo "Running formatter..."
cd "$TEMP_DIR"
git init -q
git add .
"$TEMP_DIR/fmt/bin/braiinsfmt" . 2>/dev/null
cd "$REPO_ROOT"

if $UPDATE_MODE; then
    echo "Updating snapshots..."
    for temp_file in "$TEMP_DIR"/*; do
        filename=$(basename "$temp_file")
        [[ "$filename" == "fmt" || "$filename" == ".git" ]] && continue
        cp "$temp_file" "$SCRIPT_DIR/clean/$filename"
        echo "Updated: $filename"
    done
    echo ""
    echo "Snapshots updated!"
    exit 0
fi

# Compare with expected output
echo "Comparing results..."
FAILED=0
for clean_file in "$SCRIPT_DIR/clean/"*; do
    filename=$(basename "$clean_file")
    temp_file="$TEMP_DIR/$filename"

    if [[ ! -f "$temp_file" ]]; then
        echo "SKIP: $filename (not in dirty/)"
        continue
    fi

    if diff -q "$clean_file" "$temp_file" > /dev/null 2>&1; then
        echo "PASS: $filename"
    else
        echo "FAIL: $filename"
        echo "  Expected:"
        head -5 "$clean_file" | sed 's/^/    /'
        echo "  Got:"
        head -5 "$temp_file" | sed 's/^/    /'
        FAILED=1
    fi
done

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo "All tests passed!"
    exit 0
else
    echo ""
    echo "Some tests failed!"
    echo "Run with --update to regenerate snapshots"
    exit 1
fi

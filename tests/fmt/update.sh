#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating Formatter Snapshots ==="

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_.sh"

echo "Updating snapshots..."
for temp_file in "$TEMP_DIR"/*; do
    filename=$(basename "$temp_file")
    [[ $filename == ".git" ]] && continue
    cp "$temp_file" "$SCRIPT_DIR/clean/$filename"
    echo "Updated: $filename"
done

echo ""
echo "Snapshots updated!"

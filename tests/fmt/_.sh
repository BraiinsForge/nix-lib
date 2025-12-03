#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create temp directory for test output
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
echo "Temp dir: $TEMP_DIR"

# Copy dirty files to temp
cp "$SCRIPT_DIR/dirty/"* "$TEMP_DIR/"

# Run formatter
echo "Running formatter..."
cd "$TEMP_DIR"
git init -q
git add .
braiinsfmt . 2>/dev/null
cd "$SCRIPT_DIR"

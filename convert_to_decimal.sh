#!/usr/bin/env bash

set -euo pipefail

PY_SCRIPT="python/convert_to_decimal.py"
BASE_DIR="models"

if [[ ! -f "$PY_SCRIPT" ]]; then
    echo "Error: Python script '$PY_SCRIPT' not found!"
    exit 1
fi

echo "=== Converting all .mem files under '$BASE_DIR/' ==="

# Find all .mem files recursively
find "$BASE_DIR" -type f -name "*.mem" | while read -r memfile; do
    decfile="${memfile%.mem}.dec"

    # Ensure the directory exists (it should)
    mkdir -p "$(dirname "$decfile")"

    echo "Converting: $memfile -> $decfile"
    python "$PY_SCRIPT" "$memfile" "$decfile"
done

echo "=== Done! All .mem files converted. ==="
#!/usr/bin/env bash
# Varaqa o'quvchisini kompyuterda yig'ib, serverdagi o'quvchi bilan solishtiradi.
#   bash tool/test.sh <omr-service papkasi> [varaqalar soni]
# Talab: g++, python3, opencv-python, numpy, pillow (omr-service/requirements-dev.txt).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
for f in src/quirc/*.c; do gcc -O2 -c "$f" -Isrc/quirc -o "$OUT/$(basename "$f").o"; done
g++ -O2 -std=c++17 -w -o "$OUT/omr_cli" tool/omr_cli.cpp src/edux_omr.cpp "$OUT"/*.o
python3 tool/compare.py "$OUT/omr_cli" "${1:-../../../edux/omr-service}" "${2:-48}"

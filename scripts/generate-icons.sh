#!/usr/bin/env bash
# generate-icons.sh — Generate iOS AppIcon PNGs from a source SVG.
#
# Requires: brew install librsvg
#
# Usage: scripts/generate-icons.sh
#
# Input:  assets/icon-light.svg  (the shield SVG)
#
# Outputs (1024x1024 PNG, placed into Xcode asset catalog):
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon.png        (light)
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png   (dark)
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png (tinted)
#
# Background: #0f0a00 — the default dark background from MuiTheme.ts in the
# web extension, used as the primary app background across the entire UI.
# All three icon variants use the same background and source SVG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_SVG="$REPO_ROOT/assets/icon-light.svg"
ICON_DIR="$REPO_ROOT/ShieldBee/Assets.xcassets/AppIcon.appiconset"
SIZE=1024
BG="#0f0a00"
PADDING_PCT=8   # percentage of canvas size padded on each side

INNER=$(echo "$SIZE $PADDING_PCT" | awk '{printf "%d", $1 * (1 - 2 * $2 / 100)}')

if ! command -v rsvg-convert &>/dev/null; then
  echo "Error: rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi
if ! command -v magick &>/dev/null; then
  echo "Error: magick not found. Install with: brew install imagemagick" >&2
  exit 1
fi
if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Error: missing $SOURCE_SVG" >&2
  exit 1
fi

echo "Generating app icons (${SIZE}x${SIZE}, bg=${BG}, padding=${PADDING_PCT}%)..."

for out_png in "$ICON_DIR/AppIcon.png" "$ICON_DIR/AppIcon-Dark.png" "$ICON_DIR/AppIcon-Tinted.png"; do
  echo "  → $(basename "$out_png")"
  rsvg-convert -w "$INNER" -h "$INNER" "$SOURCE_SVG" \
    | magick PNG:- -background "$BG" -gravity center -extent "${SIZE}x${SIZE}" "$out_png"
done

echo "Done. Icons written to $ICON_DIR"

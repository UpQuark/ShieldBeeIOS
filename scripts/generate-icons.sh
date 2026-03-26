#!/usr/bin/env bash
# generate-icons.sh — Generate iOS AppIcon PNGs from source SVGs.
#
# Requires: brew install librsvg
#
# Usage: scripts/generate-icons.sh
#
# Inputs (edit paths below if needed):
#   assets/icon-light.svg   — full-colour, used for light/default icon
#   assets/icon-dark.svg    — adapted for dark backgrounds (falls back to light)
#   assets/icon-tinted.svg  — monochrome silhouette; iOS applies system tint on top
#                             (falls back to light if not present)
#
# Outputs (1024×1024 PNG, placed into Xcode asset catalog):
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon.png
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png
#   ShieldBee/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASSETS_DIR="$REPO_ROOT/assets"
ICON_DIR="$REPO_ROOT/ShieldBee/Assets.xcassets/AppIcon.appiconset"

SIZE=1024

# Verify rsvg-convert is available
if ! command -v rsvg-convert &>/dev/null; then
  echo "Error: rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

convert_svg() {
  local src="$1"
  local dst="$2"
  echo "  → $(basename "$src") → $(basename "$dst")"
  rsvg-convert -w "$SIZE" -h "$SIZE" -o "$dst" "$src"
}

echo "Generating app icons (${SIZE}x${SIZE})..."

# Light / default
LIGHT_SVG="$ASSETS_DIR/icon-light.svg"
if [[ ! -f "$LIGHT_SVG" ]]; then
  echo "Error: missing $LIGHT_SVG" >&2
  exit 1
fi
convert_svg "$LIGHT_SVG" "$ICON_DIR/AppIcon.png"

# Dark — fall back to light if dedicated dark SVG not present
DARK_SVG="$ASSETS_DIR/icon-dark.svg"
if [[ -f "$DARK_SVG" ]]; then
  convert_svg "$DARK_SVG" "$ICON_DIR/AppIcon-Dark.png"
else
  echo "  → icon-dark.svg not found, copying light variant for dark slot"
  cp "$ICON_DIR/AppIcon.png" "$ICON_DIR/AppIcon-Dark.png"
fi

# Tinted — fall back to light if dedicated tinted SVG not present
TINTED_SVG="$ASSETS_DIR/icon-tinted.svg"
if [[ -f "$TINTED_SVG" ]]; then
  convert_svg "$TINTED_SVG" "$ICON_DIR/AppIcon-Tinted.png"
else
  echo "  → icon-tinted.svg not found, copying light variant for tinted slot"
  cp "$ICON_DIR/AppIcon.png" "$ICON_DIR/AppIcon-Tinted.png"
fi

echo "Done. Icons written to $ICON_DIR"

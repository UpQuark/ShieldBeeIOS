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

if ! command -v rsvg-convert &>/dev/null; then
  echo "Error: rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Error: missing $SOURCE_SVG" >&2
  exit 1
fi

render_with_bg() {
  local out_png="$1"
  local tmp
  tmp="$(mktemp /tmp/shieldbee-icon-XXXXXX.svg)"

  cat > "$tmp" <<SVGEOF
<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <rect width="128" height="128" fill="${BG}"/>
  <image xlink:href="${SOURCE_SVG}" x="0" y="0" width="128" height="128"/>
</svg>
SVGEOF

  echo "  → $(basename "$out_png")"
  rsvg-convert -w "$SIZE" -h "$SIZE" -o "$out_png" "$tmp"
  rm "$tmp"
}

echo "Generating app icons (${SIZE}x${SIZE}, bg=${BG})..."

render_with_bg "$ICON_DIR/AppIcon.png"
render_with_bg "$ICON_DIR/AppIcon-Dark.png"
render_with_bg "$ICON_DIR/AppIcon-Tinted.png"

echo "Done. Icons written to $ICON_DIR"

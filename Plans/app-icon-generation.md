# Plan: App Icon Generation from SVG

Generate all required iOS app icon variants from a source SVG using a script tied to a Makefile target. Xcode 15+ uses a single-size format: three 1024×1024 PNGs (light, dark, tinted).

## Prerequisites

- [ ] Install `librsvg` for SVG→PNG conversion: `brew install librsvg`
- [ ] Confirm source SVG exists (currently `ShieldBug/Assets.xcassets/ShieldBugLogo.imageset/Logo.svg`)

## Source Assets

- [ ] Create `assets/` directory at the repo root for icon source files
- [ ] Copy or symlink `Logo.svg` → `assets/icon-light.svg` (full-color, used as default/light variant)
- [ ] Create `assets/icon-dark.svg` — dark-mode adapted version (lighter strokes/fills for dark backgrounds)
- [ ] Create `assets/icon-tinted.svg` — monochrome/grayscale version (iOS applies system tint on top; should be single-color silhouette)

## Script

- [ ] Create `scripts/generate-icons.sh`:
  - Takes `assets/icon-light.svg`, `assets/icon-dark.svg`, `assets/icon-tinted.svg` as inputs
  - Exports each at 1024×1024 PNG using `rsvg-convert -w 1024 -h 1024`
  - Writes outputs to `ShieldBug/Assets.xcassets/AppIcon.appiconset/`:
    - `AppIcon.png` (light)
    - `AppIcon-Dark.png` (dark)
    - `AppIcon-Tinted.png` (tinted)
  - Makes the script executable (`chmod +x`)

## Wire Icons into Xcode

- [ ] Update `ShieldBug/Assets.xcassets/AppIcon.appiconset/Contents.json` to add `"filename"` keys:
  - Light entry → `"filename": "AppIcon.png"`
  - Dark entry → `"filename": "AppIcon-Dark.png"`
  - Tinted entry → `"filename": "AppIcon-Tinted.png"`

## Makefile

- [ ] Create `Makefile` at repo root with:
  ```makefile
  .PHONY: icons
  icons:
  	scripts/generate-icons.sh
  ```
- [ ] Verify `make icons` runs successfully and Xcode picks up the new PNGs

## Optional: Xcode Build Phase

- [ ] (Optional) Add a Run Script build phase in Xcode that calls `scripts/generate-icons.sh` so icons regenerate on clean builds — only if the source SVGs are expected to change often

## Validation

- [ ] Open Xcode and confirm all three icon slots (light, dark, tinted) show the correct artwork in the AppIcon asset catalog
- [ ] Build and run on simulator to verify the home screen icon appears correctly
- [ ] Test on a device with dark mode enabled

.PHONY: icons

## icons: Generate app icon PNGs from source SVGs in assets/.
## Requires: brew install librsvg
icons:
	scripts/generate-icons.sh

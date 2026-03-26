# ShieldBee iOS

Native iOS app for ShieldBee — distraction blocking via VPN tunnel with schedule support, deep-breath intervention, and PIN protection.

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- Apple Developer account (team `TNQP6G94U5`) for device builds

## Building

Open `ShieldBug.xcodeproj` in Xcode, select the **ShieldBee** scheme, and run on your device or simulator.

From the command line:

```sh
xcodebuild \
  -project ShieldBug.xcodeproj \
  -scheme ShieldBee \
  -destination "id=<DEVICE_UDID>" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build
```

> `xcrun devicectl list devices` shows UDIDs for connected devices.

## App Icons

Icons are generated from a single source SVG using `rsvg-convert`:

```sh
brew install librsvg   # one-time
make icons
```

This renders three 1024×1024 PNGs into `ShieldBee/Assets.xcassets/AppIcon.appiconset/`:

| Variant | Background | Colour |
|---------|-----------|--------|
| Light (default) | `#FF9800` | sbOrange — primary brand orange |
| Dark | `#231500` | sbDarkPaper — warm near-black |
| Tinted | `#D58F3C` | sbLogoGold — mid-tone gold; iOS applies system tint on top |

The source SVG lives at `assets/icon-light.svg`. The script (`scripts/generate-icons.sh`) wraps it with each background at render time — no separate per-variant SVG files are needed.

Run `make icons` after modifying the source SVG, then rebuild.

## Architecture

| File | Purpose |
|------|---------|
| `ShieldBeeApp.swift` | App entry point, background task registration, deep-breath/PIN guard |
| `ShieldBeeStore.swift` | Central state (block list, schedules, preferences) via Combine |
| `VPNManager.swift` | `NETunnelProviderManager` lifecycle, block list sync to extension |
| `ScheduleManager.swift` | Time-based blocking evaluation |
| `KeychainManager.swift` | PIN hash storage |
| `ShieldBee VPN Extension/` | `NEPacketTunnelProvider` — DNS interception and IP blocking |

## Plans

Implementation plans with checkboxes live in [`Plans/`](Plans/):

- [`app-icon-generation.md`](Plans/app-icon-generation.md)
- [`rename-shieldbug-to-shieldbee.md`](Plans/rename-shieldbug-to-shieldbee.md)

## Related

- Browser extension + marketing site: `../shieldbug/`
- VPN extension setup notes: [`VPN_SETUP_INSTRUCTIONS.md`](VPN_SETUP_INSTRUCTIONS.md)

# Plan: Rename ShieldBug → ShieldBee (iOS App)

Rename all occurrences of "ShieldBug" to "ShieldBee" in the iOS project — display names, bundle identifiers, Swift type names, file names, Xcode targets, and folder names.

> **Note**: The browser extension and marketing site are handled in a separate plan in the `shieldbug/` repo.

## Swift Source Files

- [ ] Rename `ShieldBug/ShieldBugApp.swift` → `ShieldBeeApp.swift` and update the struct name: `ShieldBugApp` → `ShieldBeeApp`
- [ ] Rename `ShieldBug/ShieldBugColors.swift` → `ShieldBeeColors.swift` and update any type/extension name inside
- [ ] Search all `.swift` files for remaining `ShieldBug` references (class names, comments, string literals) and update them
- [ ] Verify `ShieldBeeStore.swift` — already named correctly, check for any `ShieldBug` strings inside

## Info.plist Files

- [ ] `ShieldBug/Info.plist` — update bundle identifier background task ID:
  - `shieldbug.ShieldBug.scheduleEvaluation` → `shieldbee.ShieldBee.scheduleEvaluation`
- [ ] `ShieldBug VPN Extension/Info.plist` — update display name:
  - `"ShieldBug VPN"` → `"ShieldBee VPN"`

## Xcode Project (`ShieldBug.xcodeproj`)

- [ ] Rename targets in `project.pbxproj`:
  - `ShieldBug` → `ShieldBee`
  - `ShieldBug VPN Extension` → `ShieldBee VPN Extension`
  - `ShieldBugTests` → `ShieldBeeTests`
  - `ShieldBugUITests` → `ShieldBeeUITests`
- [ ] Update bundle identifiers for all targets in project settings:
  - e.g. `com.yourorg.shieldbug` → `com.yourorg.shieldbee` (match existing pattern)
- [ ] Rename scheme: `ShieldBug` → `ShieldBee` (in `xcshareddata/xcschemes/`)
- [ ] Rename `.xcodeproj` itself: `ShieldBug.xcodeproj` → `ShieldBee.xcodeproj`

## Folders & File References

- [ ] Rename the main group/folder in Xcode from `ShieldBug` → `ShieldBee`
  - Update `project.pbxproj` path references accordingly
- [ ] Rename `ShieldBug VPN Extension/` → `ShieldBee VPN Extension/` on disk and in project
- [ ] Rename `ShieldBugTests/` → `ShieldBeeTests/` on disk and in project
- [ ] Rename `ShieldBugUITests/` → `ShieldBeeUITests/` on disk and in project

## Asset Catalogs

- [ ] Rename `ShieldBug/Assets.xcassets/ShieldBugLogo.imageset/` → `ShieldBeeLogo.imageset/`
  - Update `Contents.json` inside if it has a name reference
  - Update any Swift references to `Image("ShieldBugLogo")` → `Image("ShieldBeeLogo")`

## Test Files

- [ ] Update `ShieldBugTests/*.swift` — class names and any string references
- [ ] Update `ShieldBugUITests/*.swift` — class names and any string references

## Scripts & Build Artifacts

- [ ] Check `scripts/` directory for any hardcoded `ShieldBug` references
- [ ] Delete `build/` artifacts and do a clean build after renaming

## Validation

- [ ] `grep -r "ShieldBug" . --include="*.swift" --include="*.plist" --include="*.json"` returns no matches (excluding this plan file)
- [ ] Project opens cleanly in Xcode with no missing file references
- [ ] App builds successfully for simulator
- [ ] VPN extension builds and links correctly
- [ ] App display name shows "ShieldBee" on the home screen

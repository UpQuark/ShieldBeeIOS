# shi-48 — Let users choose PIN or password for the app lock (default: PIN)

[Linear ticket](https://linear.app/shieldbug/issue/SHI-48)

## Background

The app lock is deliberate friction so you can't impulsively disable your own blocking.
Today it's numeric-PIN-only. Add a Settings choice between PIN (default) and Password,
and have the lock screen honour it.

## Implementation Steps

- [x] Add `LockType` enum (`pin` / `password`) and `lockType` to `UserPreferences`, defaulting to `.pin`
- [x] Give `UserPreferences` a custom `init(from:)` using `decodeIfPresent` so adding fields doesn't wipe existing stored preferences
- [x] Extend `PINEntryView` to render a masked text field in password mode, keeping the numpad for PIN
- [x] Add a `.changeType(from:to:)` mode so switching lock type verifies the current secret first
- [x] Add the lock-type picker to `SettingsView` and make its labels track the active type
- [x] Verify existing PIN users stay on `.pin` with no forced re-setup

## Notes

- Supersedes SHI-44 (full keyboard unconditionally) — this makes it a choice instead.
- Keychain storage is unchanged: a SHA-256 hash of whatever string, under the same account key,
  so existing PINs keep working.
- Changing lock type without verifying the current secret would make the lock trivially bypassable.

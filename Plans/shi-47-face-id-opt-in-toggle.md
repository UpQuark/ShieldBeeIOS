# shi-47 — Make Face ID unlock an opt-in toggle, defaulting to off

[Linear ticket](https://linear.app/shieldbug/issue/SHI-47)

## Background

The lock screen currently fires Face ID automatically and a successful scan skips the
PIN entirely, with no way to turn it off. That defeats the point of a lock whose whole
job is to add deliberate friction before you disable your own blocking.

## Implementation Steps

- [x] Add `biometricUnlockEnabled: Bool = false` to `UserPreferences`
- [x] Gate the `.onAppear` auto-prompt in `PINEntryView` on the preference
- [x] Gate the biometric button (both numpad and password layouts) on the preference
- [x] Add a Face ID / Touch ID toggle to `SettingsView`, shown only when the hardware exists
- [x] Require verifying the current secret before enabling the toggle
- [x] Update the App Lock footer text to reflect the toggle state

## Notes

- Defaults to off for existing users too — safer default, and matches what someone
  setting a lock is asking for.
- Enabling without re-verification would let anyone holding the unlocked phone turn on
  Face ID and walk past the lock from then on.

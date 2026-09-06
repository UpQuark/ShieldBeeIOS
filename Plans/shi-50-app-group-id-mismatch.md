# shi-50 — App group ID in code doesn't match the one that's entitled

[Linear ticket](https://linear.app/shieldbug/issue/SHI-50)

## Background

The app and VPN extension share the blocklist through an app group container. The code
asks for `group.shieldbee.ShieldBee`, but both targets are only entitled to (and the
provisioning profile only grants) `group.shieldbug.ShieldBug`. iOS doesn't error on an
un-entitled group — it hands back private per-process storage — so the two processes have
been reading separate copies. Confirmed on device: the group's plist sits inside the app's
own sandbox.

## Implementation Steps

- [x] Point all three code constants at the entitled group `group.shieldbug.ShieldBug`
- [x] Migrate existing data from the old private store on first launch, so users don't lose their blocklist
- [x] Delete the orphan `ShieldBee/VPNExtension.entitlements` (names a third ID, unreferenced by the project)
- [x] Log loudly in debug builds when the shared container can't be opened
- [x] Build and deploy to device, verify the plist moves out of the private container

## Notes

- Changing the ID means the app looks in a different place, so without migration every
  existing user's blocklist and settings would appear to vanish. The old store is still
  readable via the same un-entitled fallback, so a one-shot copy works.
- Left for later: renaming the group to something ShieldBee-branded. That needs a new group
  registered in the Apple developer account plus reprovisioning both targets.

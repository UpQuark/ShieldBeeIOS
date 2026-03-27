# ShieldBug iOS — Feature Roadmap

Parity target: Chrome extension feature set, adapted for iOS.

---

## Phase 1 — Core Blocking (done)

- [x] VPN tunnel using `NEPacketTunnelProvider`
- [x] Block individual domains (user-managed list)
- [x] DNS interception (NXDOMAIN for blocked domains)
- [x] IP-level blocking via split-tunnel (bypasses DNS cache)
- [x] Block list stored locally, synced to VPN extension at runtime
- [x] `ShieldBeeStore` data layer (local persistence, API-ready interface)

---

## Phase 2 — Block Management UI

### Block Sites
- [x] Wire `HomeView` (Block tab) to `ShieldBeeStore` instead of raw `UserDefaults`
- [x] Show enabled/disabled toggle per site (vs delete only)
- [x] Validate domain input (strip scheme, strip path, reject invalid)

### Block Categories
- [x] New "Categories" section in Block tab or Settings
- [x] 5 toggle cards: Social Media, News, Shopping, Video Streaming, Gambling
- [x] Each card shows representative domains (collapsed list)
- [x] Enabling a category merges its domains into the VPN block list automatically

### Master Toggle
- [x] Global on/off switch in Setup tab (already partially present via VPN connect/disconnect)
- [x] When off: VPN disconnects, nothing is blocked
- [x] When on: VPN reconnects with current block list

---

## Phase 3 — Scheduling

### Block Schedule
- [x] New "Schedule" tab
- [x] Create time intervals with start/end time pickers
- [x] Day-of-week selector per interval (multi-select)
- [x] Enable/disable individual intervals without deleting
- [x] `ScheduleManager` evaluates on app foreground and adjusts VPN automatically
- [x] Show next scheduled event in Setup tab
- [x] `BGTaskScheduler` background evaluation (needs `BGTaskSchedulerPermittedIdentifiers` in Info.plist)

---

## Phase 4 — Commitment Features

### Deep Breath (anti-impulsive unblock)
- [x] Configurable countdown (seconds) shown before settings can be changed
- [x] Triggers on app foreground — gates the whole app until timer completes
- [x] Countdown UI overlay with cancel disabled until timer completes
- [x] Duration configurable in Settings (5–60s, step 5)

### Password Protection
- [x] Optional 4-digit PIN to access the app
- [x] Stored as SHA-256 hash in Keychain (not UserDefaults)
- [x] Change PIN flow requires current PIN
- [x] Recovery: deemphasised "Forgot PIN?" clears PIN and forces immediate reset

---

## Phase 5 — Analytics

### Block Counter
- [ ] Increment counter each time VPN sends a TCP RST or NXDOMAIN
- [ ] Pass count back to main app via shared `UserDefaults` (App Group)
- [ ] Display running total in Setup tab ("X distractions blocked")
- [ ] Optional: per-domain breakdown
- [ ] Reset counter option in Settings

---

## Phase 6 — Extra Settings

### Theme
- [x] Light / Dark / System toggle in Settings
- [x] Applied via SwiftUI `preferredColorScheme`
- [x] Preference stored in `ShieldBeeStore`

### Keyword Blocking
- [ ] Block any domain whose URL contains a keyword
- [ ] Keyword list managed in Settings
- [ ] VPN extension checks hostname against keyword list at DNS intercept time
- [ ] Disabled by default, toggled in Extra Settings

---

## Data Layer Notes

`ShieldBeeStore` is the single source of truth for all config. Each method has a marked `TODO` for future API replacement:

```
func addBlockedSite(domain:)   // TODO: POST /sites
func removeBlockedSite(id:)    // TODO: DELETE /sites/:id
func setCategoryEnabled(...)   // TODO: PATCH /categories/:type
func addSchedule(...)          // TODO: POST /schedules
func updatePreferences(...)    // TODO: PATCH /preferences
```

When an API exists, replace the `UserDefaults` body with an async network call. The `@Published` properties and call sites remain unchanged.

---

## Open Questions

- Should "Deep Breath" apply to VPN toggle, or only to the block list?
- Password protection: PIN (simpler) or full password?
- Block counter: should the VPN extension write directly to shared UserDefaults, or message the main app?
- Schedule: use `BGTaskScheduler` or a system-level approach (e.g. Shortcuts integration)?
- Multi-device sync: iCloud or proprietary API?

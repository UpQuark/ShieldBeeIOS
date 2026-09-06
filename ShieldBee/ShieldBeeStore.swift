//
//  ShieldBeeStore.swift
//  ShieldBee
//
//  Central data store for all app state.
//  Currently backed by UserDefaults with JSON encoding.
//  Methods are structured so local storage can be swapped for API calls later
//  without changing call sites — replace the body of each method with a network request.
//

import Foundation
import Combine

// MARK: - Models

struct BlockedSite: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var domain: String
    var isEnabled: Bool = true
    var addedAt: Date = Date()
}

enum BlockCategoryType: String, CaseIterable, Codable, Identifiable {
    case socialMedia    = "social_media"
    case news           = "news"
    case shopping       = "shopping"
    case videoStreaming  = "video_streaming"
    case gambling       = "gambling"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .socialMedia:   return "Social Media"
        case .news:          return "News"
        case .shopping:      return "Shopping"
        case .videoStreaming: return "Video Streaming"
        case .gambling:      return "Gambling"
        }
    }
}

struct BlockCategory: Identifiable, Codable {
    var id: BlockCategoryType
    var isEnabled: Bool = false
    var customDomains: [String] = []
}

struct BlockSchedule: Identifiable, Codable {
    var id: UUID = UUID()
    var startHour: Int   = 9
    var startMinute: Int = 0
    var endHour: Int     = 17
    var endMinute: Int   = 0
    var activeDays: Set<Int> = []   // 1 = Sunday … 7 = Saturday (Calendar.weekday)
    var isEnabled: Bool  = true
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// How the app lock challenges the user. PIN is digits-only on a custom numpad;
/// password accepts any characters on the system keyboard.
enum LockType: String, Codable, CaseIterable, Identifiable {
    case pin, password
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pin:      return "PIN"
        case .password: return "Password"
        }
    }
}

struct UserPreferences: Codable {
    var theme: AppTheme         = .system
    var deepBreathEnabled: Bool = false
    var deepBreathDuration: Int = 10     // seconds
    var deterrentEnabled: Bool  = false
    var masterBlockingEnabled: Bool = true
    var lockType: LockType      = .pin
    /// Off by default: the lock exists to add friction, and a glance at the phone removes it.
    var biometricUnlockEnabled: Bool = false

    init() {}

    /// Decoded field-by-field with `decodeIfPresent` rather than relying on the synthesized
    /// initialiser. The synthesized one throws when a key is missing, which for stored
    /// preferences means the whole blob fails to decode and every setting silently resets to
    /// default. Adding any new preference would otherwise wipe existing users' settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserPreferences()
        theme                 = try c.decodeIfPresent(AppTheme.self, forKey: .theme)              ?? d.theme
        deepBreathEnabled     = try c.decodeIfPresent(Bool.self,     forKey: .deepBreathEnabled)  ?? d.deepBreathEnabled
        deepBreathDuration    = try c.decodeIfPresent(Int.self,      forKey: .deepBreathDuration) ?? d.deepBreathDuration
        deterrentEnabled      = try c.decodeIfPresent(Bool.self,     forKey: .deterrentEnabled)   ?? d.deterrentEnabled
        masterBlockingEnabled = try c.decodeIfPresent(Bool.self,     forKey: .masterBlockingEnabled) ?? d.masterBlockingEnabled
        lockType              = try c.decodeIfPresent(LockType.self, forKey: .lockType)           ?? d.lockType
        biometricUnlockEnabled = try c.decodeIfPresent(Bool.self,    forKey: .biometricUnlockEnabled) ?? d.biometricUnlockEnabled
    }
}

// MARK: - Store

@MainActor
class ShieldBeeStore: ObservableObject {

    static let shared = ShieldBeeStore()

    @Published var blockedSites: [BlockedSite]      = []
    @Published var categories: [BlockCategory]       = []
    @Published var schedules: [BlockSchedule]        = []
    @Published var preferences: UserPreferences      = UserPreferences()
    @Published var blockCount: Int                   = 0
    @Published var isLoading: Bool                   = false
    /// True while the VPN connection was opened by a schedule rather than by the user.
    /// Deliberately in-memory only: a manual connection should survive a relaunch as manual.
    @Published var isScheduleControlled: Bool        = false

    /// Must match `com.apple.security.application-groups` in both targets' entitlements and the
    /// provisioning profile. iOS does not error on an un-entitled group — it silently returns
    /// private per-process storage — so a mismatch here breaks app↔extension sharing invisibly.
    static let appGroupID = "group.shieldbug.ShieldBug"
    /// The un-entitled ID this app shipped with before SHI-50. Still readable (it resolves to
    /// the same private fallback it always did), so existing data can be migrated out of it.
    private static let legacyAppGroupID = "group.shieldbee.ShieldBee"

    private let defaults = UserDefaults(suiteName: ShieldBeeStore.appGroupID)!
    private let encoder  = JSONEncoder()
    private let decoder  = JSONDecoder()

    private init() {
        AppGroup.assertShared(defaults)
        migrateFromLegacyAppGroupIfNeeded()
        load()
    }

    /// One-shot copy out of the pre-SHI-50 app group. Between the ShieldBug→ShieldBee rename
    /// (SHI-43) and SHI-50 the app asked for a group it was not entitled to, so every write
    /// landed in private storage the VPN extension could never read.
    ///
    /// The entitled container is *not* empty — it holds pre-rename data, because the code used
    /// the entitled ID back then. That data is stale by definition: every build since the rename
    /// wrote to the private store instead. So the legacy store wins wherever it has data, and
    /// the older shared values are preserved under a backup key rather than dropped.
    private func migrateFromLegacyAppGroupIfNeeded() {
        guard !defaults.bool(forKey: Keys.legacyGroupMigrated) else { return }
        defer { defaults.set(true, forKey: Keys.legacyGroupMigrated) }

        guard let legacy = UserDefaults(suiteName: Self.legacyAppGroupID) else { return }

        let dataKeys = [Keys.blockedSites, Keys.categories, Keys.schedules, Keys.preferences]
        guard dataKeys.contains(where: { legacy.data(forKey: $0) != nil }) else { return }

        for key in dataKeys {
            guard let incoming = legacy.data(forKey: key) else { continue }
            if let existing = defaults.data(forKey: key) {
                defaults.set(existing, forKey: key + Keys.preGroupFixBackupSuffix)
            }
            defaults.set(incoming, forKey: key)
        }
        if legacy.object(forKey: Keys.blockCount) != nil {
            defaults.set(legacy.integer(forKey: Keys.blockCount), forKey: Keys.blockCount)
        }
        if let urls = legacy.stringArray(forKey: "blockedURLs") {
            defaults.set(urls, forKey: "blockedURLs")
        }
    }

    // MARK: - Blocked Sites

    func addBlockedSite(domain: String) {
        // TODO: POST /sites
        let site = BlockedSite(domain: domain)
        blockedSites.append(site)
        persist()
        syncToVPN()
    }

    func removeBlockedSite(id: UUID) {
        // TODO: DELETE /sites/:id
        blockedSites.removeAll { $0.id == id }
        persist()
        syncToVPN()
    }

    func setBlockedSiteEnabled(_ id: UUID, enabled: Bool) {
        // TODO: PATCH /sites/:id
        guard let i = blockedSites.firstIndex(where: { $0.id == id }) else { return }
        blockedSites[i].isEnabled = enabled
        persist()
        syncToVPN()
    }

    // MARK: - Categories

    func setCategoryEnabled(_ type: BlockCategoryType, enabled: Bool) {
        // TODO: PATCH /categories/:type
        if let i = categories.firstIndex(where: { $0.id == type }) {
            categories[i].isEnabled = enabled
        } else {
            categories.append(BlockCategory(id: type, isEnabled: enabled))
        }
        persist()
        syncToVPN()
    }

    func isEnabled(_ type: BlockCategoryType) -> Bool {
        categories.first(where: { $0.id == type })?.isEnabled ?? false
    }

    func addCustomDomain(_ domain: String, to type: BlockCategoryType) {
        // TODO: POST /categories/:type/domains
        if let i = categories.firstIndex(where: { $0.id == type }) {
            guard !categories[i].customDomains.contains(domain) else { return }
            categories[i].customDomains.append(domain)
        } else {
            var cat = BlockCategory(id: type, isEnabled: false)
            cat.customDomains = [domain]
            categories.append(cat)
        }
        persist()
        syncToVPN()
    }

    func removeCustomDomain(_ domain: String, from type: BlockCategoryType) {
        // TODO: DELETE /categories/:type/domains/:domain
        guard let i = categories.firstIndex(where: { $0.id == type }) else { return }
        categories[i].customDomains.removeAll { $0 == domain }
        persist()
        syncToVPN()
    }

    func customDomains(for type: BlockCategoryType) -> [String] {
        categories.first(where: { $0.id == type })?.customDomains ?? []
    }

    // MARK: - Schedules

    func addSchedule(_ schedule: BlockSchedule) {
        // TODO: POST /schedules
        schedules.append(schedule)
        persist()
    }

    func removeSchedule(id: UUID) {
        // TODO: DELETE /schedules/:id
        schedules.removeAll { $0.id == id }
        persist()
    }

    func updateSchedule(_ schedule: BlockSchedule) {
        // TODO: PATCH /schedules/:id
        guard let i = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[i] = schedule
        persist()
    }

    // MARK: - Preferences

    func updatePreferences(_ prefs: UserPreferences) {
        // TODO: PATCH /preferences
        preferences = prefs
        persist()
    }

    // MARK: - Block counter

    func incrementBlockCount() {
        // TODO: POST /stats/increment
        blockCount += 1
        defaults.set(blockCount, forKey: Keys.blockCount)
    }

    func resetBlockCount() {
        // TODO: DELETE /stats
        blockCount = 0
        defaults.set(0, forKey: Keys.blockCount)
    }

    // MARK: - VPN sync

    /// Derives the flat list of domains the VPN extension should block,
    /// combining individually blocked sites and enabled categories.
    func activeDomains() -> [String] {
        let siteDomains = blockedSites
            .filter { $0.isEnabled }
            .map { $0.domain }

        let categoryDomains = categories
            .filter { $0.isEnabled }
            .flatMap { CategoryDomains.domains(for: $0.id) + $0.customDomains }

        return Array(Set(siteDomains + categoryDomains))
    }

    /// Writes the active domain list to UserDefaults so the VPN extension picks it up,
    /// then notifies VPNManager to restart the tunnel if it is already running.
    private func syncToVPN() {
        defaults.set(activeDomains(), forKey: "blockedURLs")
        NotificationCenter.default.post(name: .blockListDidChange, object: nil)
    }

    // MARK: - Persistence

    private func load() {
        blockedSites = decode([BlockedSite].self, forKey: Keys.blockedSites) ?? []
        categories   = decode([BlockCategory].self, forKey: Keys.categories) ?? []
        schedules    = decode([BlockSchedule].self, forKey: Keys.schedules)  ?? []
        preferences  = decode(UserPreferences.self, forKey: Keys.preferences) ?? UserPreferences()
        blockCount   = defaults.integer(forKey: Keys.blockCount)

        // Migrate from the old flat-array format written directly by HomeView.
        // The old key "blockedURLs" held a [String]; new storage is store.blockedSites (JSON).
        // Guard on the absence of the new key (not emptiness of the decoded array) so that
        // users who only have categories enabled — and therefore have no individual blockedSites —
        // don't trigger this migration on every launch. syncToVPN() writes category domains to
        // "blockedURLs" too, which would otherwise be misread as individually-blocked sites.
        if defaults.data(forKey: Keys.blockedSites) == nil {
            let oldURLs = defaults.stringArray(forKey: "blockedURLs") ?? []
            if !oldURLs.isEmpty {
                blockedSites = oldURLs.map { BlockedSite(domain: $0) }
                persist()
                // "blockedURLs" already contains the correct list, so no syncToVPN needed here.
            }
        }
    }

    private func persist() {
        encode(blockedSites, forKey: Keys.blockedSites)
        encode(categories,   forKey: Keys.categories)
        encode(schedules,    forKey: Keys.schedules)
        encode(preferences,  forKey: Keys.preferences)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private enum Keys {
        static let blockedSites = "store.blockedSites"
        static let categories   = "store.categories"
        static let schedules    = "store.schedules"
        static let preferences  = "store.preferences"
        static let blockCount   = "store.blockCount"
        /// Versioned: the first cut of the migration preferred the stale shared-container data,
        /// so the key is bumped to let the corrected logic run once more.
        static let legacyGroupMigrated = "store.legacyAppGroupMigrated.v2"
        static let preGroupFixBackupSuffix = ".preAppGroupFix"
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let blockListDidChange = Notification.Name("shieldbug.blockListDidChange")
}

// MARK: - Category domain lists (placeholder)

enum CategoryDomains {
    static func domains(for category: BlockCategoryType) -> [String] {
        // TODO: load from bundled JSON or API
        switch category {
        case .socialMedia:
            return [
                "facebook.com", "twitter.com", "x.com", "instagram.com", "tiktok.com",
                "reddit.com", "snapchat.com", "pinterest.com", "linkedin.com", "tumblr.com",
                "discord.com", "threads.net", "bsky.app", "mastodon.social", "vk.com",
                "telegram.org", "t.me", "whatsapp.com", "weibo.com", "qq.com",
                "bereal.com", "clubhouse.com", "meetup.com", "nextdoor.com", "quora.com",
            ]
        case .news:
            return [
                "bbc.com", "cnn.com", "theguardian.com", "nytimes.com", "dailymail.co.uk",
                "foxnews.com", "huffpost.com", "washingtonpost.com", "wsj.com", "bloomberg.com",
                "reuters.com", "apnews.com", "nbcnews.com", "cbsnews.com", "msnbc.com",
                "politico.com", "theatlantic.com", "vox.com", "npr.org", "time.com",
                "usatoday.com", "newsweek.com", "nypost.com", "independent.co.uk", "techcrunch.com",
                "theverge.com", "wired.com", "arstechnica.com", "businessinsider.com", "vice.com",
                "buzzfeed.com", "telegraph.co.uk", "sky.com", "abcnews.go.com", "slate.com",
            ]
        case .shopping:
            return [
                "amazon.com", "ebay.com", "etsy.com", "walmart.com", "target.com",
                "asos.com", "aliexpress.com", "bestbuy.com", "costco.com", "newegg.com",
                "wish.com", "shein.com", "temu.com", "hm.com", "zara.com",
                "nordstrom.com", "macys.com", "wayfair.com", "chewy.com", "poshmark.com",
                "depop.com", "vinted.com", "mercari.com", "craigslist.org", "homedepot.com",
                "lowes.com", "shopee.com", "lazada.com", "overstock.com", "gap.com",
            ]
        case .videoStreaming:
            return [
                "youtube.com", "netflix.com", "hulu.com", "disneyplus.com", "twitch.tv",
                "vimeo.com", "dailymotion.com", "max.com", "hbomax.com", "peacocktv.com",
                "paramountplus.com", "primevideo.com", "crunchyroll.com", "tubi.com", "pluto.tv",
                "mubi.com", "discoveryplus.com", "espn.com", "fubo.tv", "kick.com",
                "rumble.com", "bilibili.com", "sling.com", "curiositystream.com", "plex.tv",
            ]
        case .gambling:
            return [
                "bet365.com", "draftkings.com", "fanduel.com", "pokerstars.com", "betway.com",
                "888casino.com", "williamhill.com", "ladbrokes.com", "betfair.com", "paddypower.com",
                "betmgm.com", "caesarscasino.com", "unibet.com", "bwin.com", "bovada.lv",
                "mybookie.ag", "pointsbet.com", "hardrock.bet", "betonline.ag", "sportsbetting.ag",
                "1xbet.com", "leovegas.com", "casumo.com", "betsson.com", "22bet.com",
            ]
        }
    }
}

// MARK: - App group diagnostics

enum AppGroup {
    /// iOS returns a usable `UserDefaults` for an app group the process isn't entitled to — it
    /// just isn't shared with anyone. That failure mode is invisible at runtime, so check it
    /// explicitly: a shared suite has a container URL, the private fallback does not.
    static func assertShared(_ defaults: UserDefaults, id: String = ShieldBeeStore.appGroupID) {
        #if DEBUG
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) == nil {
            assertionFailure("""
                App group "\(id)" is not entitled for this target. UserDefaults will silently \
                fall back to private storage and the app and VPN extension will not share data. \
                Check com.apple.security.application-groups in the entitlements files.
                """)
        }
        #endif
    }
}

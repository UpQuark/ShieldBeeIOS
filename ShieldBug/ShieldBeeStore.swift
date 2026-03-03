//
//  ShieldBeeStore.swift
//  ShieldBug
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

struct UserPreferences: Codable {
    var theme: AppTheme         = .system
    var deepBreathEnabled: Bool = false
    var deepBreathDuration: Int = 10     // seconds
    var deterrentEnabled: Bool  = false
    var masterBlockingEnabled: Bool = true
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

    private static let appGroupID = "group.shieldbug.ShieldBug"
    private let defaults = UserDefaults(suiteName: ShieldBeeStore.appGroupID)!
    private let encoder  = JSONEncoder()
    private let decoder  = JSONDecoder()

    private init() {
        load()
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
        if blockedSites.isEmpty {
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

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

    private let defaults = UserDefaults.standard
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
            .flatMap { CategoryDomains.domains(for: $0.id) }

        return Array(Set(siteDomains + categoryDomains))
    }

    /// Writes the active domain list to UserDefaults so the VPN extension picks it up.
    private func syncToVPN() {
        UserDefaults.standard.set(activeDomains(), forKey: "blockedURLs")
    }

    // MARK: - Persistence

    private func load() {
        blockedSites = decode([BlockedSite].self, forKey: Keys.blockedSites) ?? []
        categories   = decode([BlockCategory].self, forKey: Keys.categories) ?? []
        schedules    = decode([BlockSchedule].self, forKey: Keys.schedules)  ?? []
        preferences  = decode(UserPreferences.self, forKey: Keys.preferences) ?? UserPreferences()
        blockCount   = defaults.integer(forKey: Keys.blockCount)
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

// MARK: - Category domain lists (placeholder)

enum CategoryDomains {
    static func domains(for category: BlockCategoryType) -> [String] {
        // TODO: load from bundled JSON or API
        switch category {
        case .socialMedia:
            return ["facebook.com", "twitter.com", "instagram.com", "tiktok.com",
                    "reddit.com", "snapchat.com", "pinterest.com", "linkedin.com",
                    "tumblr.com", "discord.com"]
        case .news:
            return ["bbc.com", "cnn.com", "theguardian.com", "nytimes.com",
                    "dailymail.co.uk", "foxnews.com", "huffpost.com"]
        case .shopping:
            return ["amazon.com", "ebay.com", "etsy.com", "walmart.com",
                    "target.com", "asos.com", "aliexpress.com"]
        case .videoStreaming:
            return ["youtube.com", "netflix.com", "hulu.com", "disneyplus.com",
                    "twitch.tv", "vimeo.com", "dailymotion.com"]
        case .gambling:
            return ["bet365.com", "draftkings.com", "fanduel.com", "pokerstars.com",
                    "betway.com", "888casino.com"]
        }
    }
}

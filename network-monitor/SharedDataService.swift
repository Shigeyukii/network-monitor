import Foundation

struct SharedDeviceStatus: Codable, Identifiable {
    var id: UUID
    var name: String
    var ipAddress: String
    var groupName: String
    var isUp: Bool?
    var responseTimeMs: Double?
    var lastChecked: Date?
}

enum SharedDataService {
    static let appGroupID = "group.starmanblog.net.network-monitor"
    static let statusKey  = "sharedDeviceStatuses"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ statuses: [SharedDeviceStatus]) {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        defaults.set(data, forKey: statusKey)
    }

    static func load() -> [SharedDeviceStatus] {
        guard let data = defaults.data(forKey: statusKey),
              let statuses = try? JSONDecoder().decode([SharedDeviceStatus].self, from: data)
        else { return [] }
        return statuses
    }
}

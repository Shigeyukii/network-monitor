import Foundation
import SwiftData

@Model
final class Device {
    var id: UUID
    var name: String
    var ipAddress: String
    var groupName: String
    var isMonitored: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var pingRecords: [PingRecord] = []

    @Relationship(deleteRule: .cascade)
    var tcpPorts: [TCPPort] = []

    init(name: String, ipAddress: String, groupName: String = "", isMonitored: Bool = true) {
        self.id = UUID()
        self.name = name
        self.ipAddress = ipAddress
        self.groupName = groupName
        self.isMonitored = isMonitored
        self.createdAt = Date()
    }

    var latestPingRecord: PingRecord? {
        pingRecords.max(by: { $0.timestamp < $1.timestamp })
    }

    var uptimePercentage: Double {
        let recent = pingRecords.filter { $0.timestamp > Date().addingTimeInterval(-86400) }
        guard !recent.isEmpty else { return 0 }
        return Double(recent.filter { $0.isReachable }.count) / Double(recent.count) * 100
    }
}

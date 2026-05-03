import Foundation
import SwiftData

@Model
final class PingRecord {
    var timestamp: Date
    var isReachable: Bool
    var responseTimeMs: Double?

    @Relationship(inverse: \Device.pingRecords)
    var device: Device?

    init(isReachable: Bool, responseTimeMs: Double?, device: Device) {
        self.timestamp = Date()
        self.isReachable = isReachable
        self.responseTimeMs = responseTimeMs
        self.device = device
    }
}

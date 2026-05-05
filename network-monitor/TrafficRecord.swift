import Foundation
import SwiftData

@Model
final class TrafficRecord {
    var timestamp: Date
    var inOctets: UInt64
    var outOctets: UInt64
    var inBitsPerSec: Double?
    var outBitsPerSec: Double?

    @Relationship(inverse: \Device.trafficRecords)
    var device: Device?

    init(inOctets: UInt64, outOctets: UInt64, device: Device) {
        self.timestamp = Date()
        self.inOctets = inOctets
        self.outOctets = outOctets
        self.inBitsPerSec = nil
        self.outBitsPerSec = nil
        self.device = device
    }
}

extension TrafficRecord {
    static func formatBps(_ bps: Double) -> String {
        switch bps {
        case ..<1_000:       return String(format: "%.0f bps", bps)
        case ..<1_000_000:   return String(format: "%.1f Kbps", bps / 1_000)
        case ..<1_000_000_000: return String(format: "%.1f Mbps", bps / 1_000_000)
        default:             return String(format: "%.1f Gbps", bps / 1_000_000_000)
        }
    }
}

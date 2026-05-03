import Foundation
import SwiftData

@Model
final class TCPPort {
    var port: Int
    var label: String

    @Relationship(inverse: \Device.tcpPorts)
    var device: Device?

    @Relationship(deleteRule: .cascade)
    var tcpRecords: [TCPRecord] = []

    init(port: Int, label: String, device: Device) {
        self.port = port
        self.label = label
        self.device = device
    }

    var latestRecord: TCPRecord? {
        tcpRecords.max(by: { $0.timestamp < $1.timestamp })
    }
}

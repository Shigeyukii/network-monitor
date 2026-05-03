import Foundation
import SwiftData

@Model
final class TCPRecord {
    var timestamp: Date
    var isReachable: Bool

    @Relationship(inverse: \TCPPort.tcpRecords)
    var tcpPort: TCPPort?

    init(isReachable: Bool, tcpPort: TCPPort) {
        self.timestamp = Date()
        self.isReachable = isReachable
        self.tcpPort = tcpPort
    }
}

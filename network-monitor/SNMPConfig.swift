import Foundation
import SwiftData

@Model
final class SNMPConfig {
    var community: String
    var version: Int        // 0 = v1, 1 = v2c
    var interfaceIndex: Int
    var isEnabled: Bool

    @Relationship(inverse: \Device.snmpConfig)
    var device: Device?

    init(community: String = "public", version: Int = 1, interfaceIndex: Int = 1) {
        self.community = community
        self.version = version
        self.interfaceIndex = interfaceIndex
        self.isEnabled = true
    }

    var versionLabel: String { version == 0 ? "v1" : "v2c" }
}

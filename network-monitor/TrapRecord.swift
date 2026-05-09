import Foundation
import SwiftData

@Model
final class TrapRecord {
    var timestamp: Date
    var sourceIP: String
    var snmpVersion: Int      // 1 = v1, 2 = v2c
    var community: String
    var trapName: String      // "linkDown" / "linkUp" など
    var trapOID: String       // トラップ種別 OID
    var varbindsJSON: String  // {"OID": "値"} の JSON 文字列
    var isRead: Bool = false

    init(
        sourceIP: String,
        snmpVersion: Int,
        community: String,
        trapName: String,
        trapOID: String,
        varbindsJSON: String = "{}"
    ) {
        self.timestamp = Date()
        self.sourceIP = sourceIP
        self.snmpVersion = snmpVersion
        self.community = community
        self.trapName = trapName
        self.trapOID = trapOID
        self.varbindsJSON = varbindsJSON
    }

    var varbinds: [String: String] {
        (try? JSONDecoder().decode([String: String].self,
                                   from: Data(varbindsJSON.utf8))) ?? [:]
    }

    var trapIcon: String {
        switch trapName {
        case "linkUp":               return "link"
        case "linkDown":             return "link.badge.minus"
        case "coldStart", "warmStart": return "arrow.clockwise"
        case "authenticationFailure": return "lock.trianglebadge.exclamationmark.fill"
        default:                     return "bell.fill"
        }
    }

    var trapColor: String {
        switch trapName {
        case "linkUp":               return "green"
        case "linkDown":             return "red"
        case "authenticationFailure": return "orange"
        default:                     return "blue"
        }
    }
}

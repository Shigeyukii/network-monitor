import Foundation
import Network
import SwiftData

// MARK: - Parsed Trap (intermediate struct)

struct ParsedTrap {
    var sourceIP: String
    var version: Int
    var community: String
    var trapName: String
    var trapOID: String
    var varbinds: [String: String]
}

// MARK: - Trap Receiver

@Observable
@MainActor
final class SNMPTrapReceiver {
    static let shared = SNMPTrapReceiver()

    var isListening = false
    var listenPort: UInt16 = 10162
    var unreadCount = 0
    var lastError: String? = nil

    private var listener: NWListener?
    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Start / Stop

    func start(port: UInt16, context: ModelContext) {
        self.modelContext = context
        self.listenPort = port
        guard !isListening else { return }

        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let listener = try NWListener(using: params, on: nwPort)

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handle(connection: connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isListening = false
                        self?.lastError = error.localizedDescription
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    func markAllRead(context: ModelContext) {
        let desc = FetchDescriptor<TrapRecord>(predicate: #Predicate { !$0.isRead })
        (try? context.fetch(desc))?.forEach { $0.isRead = true }
        try? context.save()
        unreadCount = 0
    }

    // MARK: - Connection Handling

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(from: connection)
    }

    private func receive(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let data, !data.isEmpty else { return }

            let sourceIP: String
            if case .hostPort(let host, _) = connection.endpoint {
                sourceIP = "\(host)"
            } else {
                sourceIP = "unknown"
            }

            if let trap = SNMPTrapParser.parse(data: data, sourceIP: sourceIP) {
                Task { @MainActor in
                    self?.saveTrap(trap)
                }
            }
            // UDP は都度 receiveMessage を呼ぶ必要はないが、同一接続で複数受信する場合に備える
            if error == nil { self?.receive(from: connection) }
        }
    }

    private func saveTrap(_ trap: ParsedTrap) {
        guard let context = modelContext else { return }
        let varbindsData = (try? JSONEncoder().encode(trap.varbinds)) ?? Data()
        let varbindsJSON = String(data: varbindsData, encoding: .utf8) ?? "{}"

        let record = TrapRecord(
            sourceIP: trap.sourceIP,
            snmpVersion: trap.version,
            community: trap.community,
            trapName: trap.trapName,
            trapOID: trap.trapOID,
            varbindsJSON: varbindsJSON
        )
        context.insert(record)
        try? context.save()
        unreadCount += 1

        // ローカル通知
        NotificationService.shared.sendTrapAlert(
            sourceIP: trap.sourceIP,
            trapName: trap.trapName
        )
    }
}

// MARK: - Parser

enum SNMPTrapParser {

    // 既知のトラップ OID → 名前
    private static let knownTraps: [String: String] = [
        "1.3.6.1.6.3.1.1.5.1": "coldStart",
        "1.3.6.1.6.3.1.1.5.2": "warmStart",
        "1.3.6.1.6.3.1.1.5.3": "linkDown",
        "1.3.6.1.6.3.1.1.5.4": "linkUp",
        "1.3.6.1.6.3.1.1.5.5": "authenticationFailure",
        "1.3.6.1.6.3.1.1.5.6": "egpNeighborLoss",
    ]

    private static let snmpTrapOID = "1.3.6.1.6.3.1.1.4.1.0"

    static func parse(data: Data, sourceIP: String) -> ParsedTrap? {
        let bytes = Array(data)
        var pos = 0
        guard bytes.count > 2 else { return nil }

        // 外側 SEQUENCE
        guard bytes[pos] == 0x30 else { return nil }
        pos += 1; skipLength(bytes, pos: &pos)

        // version
        guard bytes[pos] == 0x02 else { return nil }
        pos += 1
        let vLen = parseLength(bytes, pos: &pos)
        guard pos + vLen <= bytes.count else { return nil }
        let version = Int(bytes[pos]) + 1   // 0→v1, 1→v2c
        pos += vLen

        // community
        guard bytes[pos] == 0x04 else { return nil }
        pos += 1
        let cLen = parseLength(bytes, pos: &pos)
        guard pos + cLen <= bytes.count else { return nil }
        let community = String(bytes: bytes[pos..<pos + cLen], encoding: .utf8) ?? "unknown"
        pos += cLen

        guard pos < bytes.count else { return nil }
        let pduType = bytes[pos]; pos += 1
        skipLength(bytes, pos: &pos)

        switch pduType {
        case 0xA4:  // v1 Trap
            return parseV1(bytes: bytes, pos: &pos,
                           sourceIP: sourceIP, version: version, community: community)
        case 0xA7:  // v2c Trap
            return parseV2c(bytes: bytes, pos: &pos,
                            sourceIP: sourceIP, version: version, community: community)
        default:
            return nil
        }
    }

    // MARK: v1 Trap

    private static func parseV1(
        bytes: [UInt8], pos: inout Int,
        sourceIP: String, version: Int, community: String
    ) -> ParsedTrap? {
        // enterprise OID
        guard bytes[pos] == 0x06 else { return nil }
        pos += 1
        let oidLen = parseLength(bytes, pos: &pos)
        let enterpriseOID = decodeOID(Array(bytes[pos..<min(pos + oidLen, bytes.count)]))
        pos += oidLen

        // agentAddr (0x40 = IpAddress)
        if bytes[pos] == 0x40 {
            pos += 1; let l = parseLength(bytes, pos: &pos); pos += l
        }

        // genericTrap
        guard bytes[pos] == 0x02 else { return nil }
        pos += 1
        let gtLen = parseLength(bytes, pos: &pos)
        let genericTrap = gtLen > 0 ? Int(bytes[pos]) : 0
        pos += gtLen

        // specificTrap
        guard bytes[pos] == 0x02 else { return nil }
        pos += 1
        let stLen = parseLength(bytes, pos: &pos)
        let specificTrap = stLen > 0 ? Int(bytes[pos]) : 0
        pos += stLen

        // timeTicks
        if bytes[pos] == 0x43 {
            pos += 1; let l = parseLength(bytes, pos: &pos); pos += l
        }

        // varbinds
        let varbinds = parseVarbinds(bytes: bytes, pos: &pos)

        let trapName: String
        let trapOID: String
        if genericTrap == 6 {
            trapOID = enterpriseOID + ".0.\(specificTrap)"
            trapName = knownTraps[trapOID] ?? "enterpriseSpecific.\(specificTrap)"
        } else {
            trapOID = enterpriseOID
            trapName = v1GenericName(genericTrap)
        }

        return ParsedTrap(
            sourceIP: sourceIP, version: version, community: community,
            trapName: trapName, trapOID: trapOID, varbinds: varbinds
        )
    }

    // MARK: v2c Trap

    private static func parseV2c(
        bytes: [UInt8], pos: inout Int,
        sourceIP: String, version: Int, community: String
    ) -> ParsedTrap? {
        // request-id, error-status, error-index をスキップ
        for _ in 0..<3 {
            guard pos < bytes.count, bytes[pos] == 0x02 else { return nil }
            pos += 1; let l = parseLength(bytes, pos: &pos); pos += l
        }

        let varbinds = parseVarbinds(bytes: bytes, pos: &pos)

        // snmpTrapOID.0 から trapOID を取得
        let trapOID = varbinds[snmpTrapOID] ?? ""
        let trapName = knownTraps[trapOID] ?? (trapOID.isEmpty ? "unknown" : trapOID.components(separatedBy: ".").suffix(3).joined(separator: "."))

        return ParsedTrap(
            sourceIP: sourceIP, version: version, community: community,
            trapName: trapName, trapOID: trapOID, varbinds: varbinds
        )
    }

    // MARK: - BER Helpers

    private static func parseVarbinds(bytes: [UInt8], pos: inout Int) -> [String: String] {
        var result: [String: String] = [:]
        guard pos < bytes.count, bytes[pos] == 0x30 else { return result }
        pos += 1; skipLength(bytes, pos: &pos)

        while pos < bytes.count - 1 {
            guard bytes[pos] == 0x30 else { break }
            pos += 1
            let vbLen = parseLength(bytes, pos: &pos)
            let vbEnd = min(pos + vbLen, bytes.count)

            if pos < bytes.count, bytes[pos] == 0x06 {
                pos += 1
                let oidLen = parseLength(bytes, pos: &pos)
                guard pos + oidLen <= bytes.count else { pos = vbEnd; continue }
                let oid = decodeOID(Array(bytes[pos..<pos + oidLen]))
                pos += oidLen

                guard pos < vbEnd else { pos = vbEnd; continue }
                let valueType = bytes[pos]; pos += 1
                let valueLen = parseLength(bytes, pos: &pos)
                guard pos + valueLen <= bytes.count else { pos = vbEnd; continue }
                let valueStr = decodeValueString(type: valueType,
                                                  bytes: Array(bytes[pos..<pos + valueLen]))
                pos += valueLen
                result[oid] = valueStr
            }
            pos = vbEnd
        }
        return result
    }

    private static func parseLength(_ bytes: [UInt8], pos: inout Int) -> Int {
        guard pos < bytes.count else { return 0 }
        let first = bytes[pos]; pos += 1
        if first & 0x80 == 0 { return Int(first) }
        let n = Int(first & 0x7F)
        var length = 0
        for _ in 0..<n {
            guard pos < bytes.count else { break }
            length = (length << 8) | Int(bytes[pos]); pos += 1
        }
        return length
    }

    private static func skipLength(_ bytes: [UInt8], pos: inout Int) {
        _ = parseLength(bytes, pos: &pos)
    }

    private static func decodeOID(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var parts: [UInt] = [UInt(bytes[0]) / 40, UInt(bytes[0]) % 40]
        var pos = 1
        while pos < bytes.count {
            var value: UInt = 0
            repeat {
                guard pos < bytes.count else { break }
                let b = bytes[pos]; pos += 1
                value = (value << 7) | UInt(b & 0x7F)
                if b & 0x80 == 0 { break }
            } while true
            parts.append(value)
        }
        return parts.map { String($0) }.joined(separator: ".")
    }

    private static func decodeValueString(type: UInt8, bytes: [UInt8]) -> String {
        switch type {
        case 0x02:  // INTEGER
            var v = bytes.first.map { Int8(bitPattern: $0) }.map { Int($0) } ?? 0
            for b in bytes.dropFirst() { v = (v << 8) | Int(b) }
            return "\(v)"
        case 0x04:  // OCTET STRING
            return String(bytes: bytes, encoding: .utf8)
                ?? bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        case 0x06:  // OID
            return decodeOID(bytes)
        case 0x40:  // IpAddress
            return bytes.prefix(4).map { String($0) }.joined(separator: ".")
        case 0x41, 0x42, 0x43:  // Counter32, Gauge32, TimeTicks
            var v: UInt32 = 0
            for b in bytes.prefix(4) { v = (v << 8) | UInt32(b) }
            return "\(v)"
        case 0x46:  // Counter64
            var v: UInt64 = 0
            for b in bytes.prefix(8) { v = (v << 8) | UInt64(b) }
            return "\(v)"
        default:
            return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }

    private static func v1GenericName(_ type: Int) -> String {
        switch type {
        case 0: return "coldStart"
        case 1: return "warmStart"
        case 2: return "linkDown"
        case 3: return "linkUp"
        case 4: return "authenticationFailure"
        case 5: return "egpNeighborLoss"
        default: return "enterpriseSpecific"
        }
    }
}

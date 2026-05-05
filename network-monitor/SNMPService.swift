import Foundation
import Darwin

// MARK: - SNMP Value Types

enum SNMPValue {
    case integer(Int)
    case counter32(UInt32)
    case counter64(UInt64)
    case gauge32(UInt32)
    case timeTicks(UInt32)
    case octetString(Data)
    case objectID(String)
    case null
    case noSuchObject
    case noSuchInstance
    case unknown

    var asUInt64: UInt64? {
        switch self {
        case .integer(let v):   return v >= 0 ? UInt64(v) : nil
        case .counter32(let v): return UInt64(v)
        case .counter64(let v): return v
        case .gauge32(let v):   return UInt64(v)
        default:                return nil
        }
    }
}

enum SNMPError: LocalizedError {
    case socketError
    case sendError
    case timeout
    case parseError(String)
    case errorStatus(Int)

    var errorDescription: String? {
        switch self {
        case .socketError:        return "ソケット作成失敗"
        case .sendError:          return "送信失敗"
        case .timeout:            return "タイムアウト"
        case .parseError(let m):  return "パースエラー: \(m)"
        case .errorStatus(let s): return "SNMP エラーステータス: \(s)"
        }
    }
}

// MARK: - SNMP Service

struct SNMPService {

    /// SNMP GET リクエストを送信し、OID → SNMPValue の辞書を返す
    nonisolated func get(
        host: String,
        community: String,
        oids: [String],
        version: Int = 1,
        timeoutSeconds: Double = 3
    ) async throws -> [String: SNMPValue] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try Self.perform(
                        host: host, community: community,
                        oids: oids, version: version,
                        timeoutSeconds: timeoutSeconds
                    )
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Core UDP Implementation

    private static func perform(
        host: String, community: String,
        oids: [String], version: Int,
        timeoutSeconds: Double
    ) throws -> [String: SNMPValue] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "161", &hints, &res) == 0, let res else {
            throw SNMPError.socketError
        }
        defer { freeaddrinfo(res) }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { throw SNMPError.socketError }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: Int(timeoutSeconds), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let requestID = Int32.random(in: 1...Int32.max)
        let packet = buildGetRequest(version: version, community: community,
                                     requestID: requestID, oids: oids)
        let sent = packet.withUnsafeBytes { ptr in
            sendto(sock, ptr.baseAddress!, ptr.count, 0,
                   res.pointee.ai_addr, res.pointee.ai_addrlen)
        }
        guard sent > 0 else { throw SNMPError.sendError }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = recv(sock, &buffer, buffer.count, 0)
        guard received > 0 else { throw SNMPError.timeout }

        return try parseResponse(Data(buffer.prefix(received)), requestedOIDs: oids)
    }

    // MARK: - Packet Builder (ASN.1 BER)

    private static func buildGetRequest(
        version: Int, community: String,
        requestID: Int32, oids: [String]
    ) -> Data {
        // VarBindList
        var varbindList: [UInt8] = []
        for oid in oids {
            let oidBytes = encodeOID(oid)
            let varbind = tlv(0x06, oidBytes) + tlv(0x05, [])   // OID + NULL
            varbindList += tlv(0x30, Array(varbind))
        }

        // GetRequest PDU (0xA0)
        let pdu = tlv(0x02, encodeInteger(Int(requestID)))  // request-id
               + tlv(0x02, [0])                              // error-status
               + tlv(0x02, [0])                              // error-index
               + tlv(0x30, varbindList)                      // varbind-list

        // Outer SEQUENCE
        let message = tlv(0x02, [UInt8(version)])            // version
                    + tlv(0x04, Array(community.utf8))        // community
                    + tlv(0xA0, Array(pdu))                   // PDU

        return Data(tlv(0x30, Array(message)))
    }

    // MARK: - Response Parser

    private static func parseResponse(
        _ data: Data,
        requestedOIDs: [String]
    ) throws -> [String: SNMPValue] {
        var pos = 0
        let bytes = Array(data)

        // Outer SEQUENCE
        try expect(bytes, pos: &pos, type: 0x30, label: "outer SEQUENCE")
        skipLength(bytes, pos: &pos)

        // Version
        try expect(bytes, pos: &pos, type: 0x02, label: "version")
        skip(bytes, pos: &pos, n: parseLength(bytes, pos: &pos))

        // Community
        try expect(bytes, pos: &pos, type: 0x04, label: "community")
        skip(bytes, pos: &pos, n: parseLength(bytes, pos: &pos))

        // GetResponse PDU (0xA2)
        try expect(bytes, pos: &pos, type: 0xA2, label: "response PDU")
        skipLength(bytes, pos: &pos)

        // Request ID
        try expect(bytes, pos: &pos, type: 0x02, label: "request-id")
        skip(bytes, pos: &pos, n: parseLength(bytes, pos: &pos))

        // Error Status
        try expect(bytes, pos: &pos, type: 0x02, label: "error-status")
        let esLen = parseLength(bytes, pos: &pos)
        let errorStatus = esLen > 0 ? Int(bytes[pos]) : 0
        pos += esLen
        if errorStatus != 0 { throw SNMPError.errorStatus(errorStatus) }

        // Error Index
        try expect(bytes, pos: &pos, type: 0x02, label: "error-index")
        skip(bytes, pos: &pos, n: parseLength(bytes, pos: &pos))

        // VarBind List
        try expect(bytes, pos: &pos, type: 0x30, label: "varbind list")
        skipLength(bytes, pos: &pos)

        var result: [String: SNMPValue] = [:]
        var oidIdx = 0

        while pos < bytes.count - 1 {
            guard bytes[pos] == 0x30 else { break }
            pos += 1
            let vbLen = parseLength(bytes, pos: &pos)
            let vbEnd = pos + vbLen
            guard vbEnd <= bytes.count else { break }

            // OID
            if bytes[pos] == 0x06 {
                pos += 1
                let oidLen = parseLength(bytes, pos: &pos)
                guard pos + oidLen <= bytes.count else { break }
                let oidBytes = Array(bytes[pos..<pos + oidLen])
                pos += oidLen

                // Value
                guard pos < vbEnd else { pos = vbEnd; continue }
                let valueType = bytes[pos]; pos += 1
                let valueLen = parseLength(bytes, pos: &pos)
                guard pos + valueLen <= bytes.count else { pos = vbEnd; continue }
                let valueBytes = Array(bytes[pos..<pos + valueLen])
                pos += valueLen

                let key = oidIdx < requestedOIDs.count
                    ? requestedOIDs[oidIdx]
                    : decodeOID(oidBytes)
                result[key] = decodeValue(type: valueType, bytes: valueBytes)
                oidIdx += 1
            }
            pos = vbEnd
        }
        return result
    }

    // MARK: - BER Encode Helpers

    private static func tlv(_ type: UInt8, _ value: [UInt8]) -> [UInt8] {
        [type] + encodeLength(value.count) + value
    }

    private static func encodeLength(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        if n < 0x100 { return [0x81, UInt8(n)] }
        return [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
    }

    private static func encodeInteger(_ value: Int) -> [UInt8] {
        if value == 0 { return [0] }
        var bytes: [UInt8] = []
        var v = value
        while v != 0 {
            bytes.insert(UInt8(bitPattern: Int8(truncatingIfNeeded: v)), at: 0)
            v >>= 8
        }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return bytes
    }

    private static func encodeOID(_ oid: String) -> [UInt8] {
        let parts = oid.split(separator: ".").compactMap { UInt($0) }
        guard parts.count >= 2 else { return [] }
        var bytes: [UInt8] = [UInt8(40 * parts[0] + parts[1])]
        for part in parts.dropFirst(2) {
            bytes += encodeBase128(part)
        }
        return bytes
    }

    private static func encodeBase128(_ value: UInt) -> [UInt8] {
        if value == 0 { return [0] }
        var bytes: [UInt8] = []
        var v = value
        while v > 0 {
            bytes.insert(UInt8(v & 0x7F), at: 0)
            v >>= 7
        }
        for i in 0..<bytes.count - 1 { bytes[i] |= 0x80 }
        return bytes
    }

    // MARK: - BER Decode Helpers

    private static func parseLength(_ bytes: [UInt8], pos: inout Int) -> Int {
        guard pos < bytes.count else { return 0 }
        let first = bytes[pos]; pos += 1
        if first & 0x80 == 0 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        var length = 0
        for _ in 0..<numBytes {
            guard pos < bytes.count else { break }
            length = (length << 8) | Int(bytes[pos])
            pos += 1
        }
        return length
    }

    private static func skipLength(_ bytes: [UInt8], pos: inout Int) {
        _ = parseLength(bytes, pos: &pos)
    }

    private static func skip(_ bytes: [UInt8], pos: inout Int, n: Int) {
        pos = min(pos + n, bytes.count)
    }

    private static func expect(
        _ bytes: [UInt8], pos: inout Int,
        type expectedType: UInt8, label: String
    ) throws {
        guard pos < bytes.count else { throw SNMPError.parseError("EOF at \(label)") }
        guard bytes[pos] == expectedType else {
            throw SNMPError.parseError("Expected 0x\(String(expectedType, radix: 16)) at \(label), got 0x\(String(bytes[pos], radix: 16))")
        }
        pos += 1
    }

    private static func decodeOID(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var components: [UInt] = [UInt(bytes[0]) / 40, UInt(bytes[0]) % 40]
        var pos = 1
        while pos < bytes.count {
            var value: UInt = 0
            repeat {
                guard pos < bytes.count else { break }
                let b = bytes[pos]; pos += 1
                value = (value << 7) | UInt(b & 0x7F)
                if b & 0x80 == 0 { break }
            } while true
            components.append(value)
        }
        return components.map { String($0) }.joined(separator: ".")
    }

    private static func decodeValue(type: UInt8, bytes: [UInt8]) -> SNMPValue {
        switch type {
        case 0x02:  // INTEGER
            var v = bytes.first.map { Int8(bitPattern: $0) }.map { Int($0) } ?? 0
            for b in bytes.dropFirst() { v = (v << 8) | Int(b) }
            return .integer(v)
        case 0x41:  // Counter32
            return .counter32(decodeUInt32(bytes))
        case 0x42:  // Gauge32
            return .gauge32(decodeUInt32(bytes))
        case 0x43:  // TimeTicks
            return .timeTicks(decodeUInt32(bytes))
        case 0x46:  // Counter64
            var v: UInt64 = 0
            for b in bytes.prefix(8) { v = (v << 8) | UInt64(b) }
            return .counter64(v)
        case 0x04:  // OCTET STRING
            return .octetString(Data(bytes))
        case 0x06:  // OID
            return .objectID(decodeOID(bytes))
        case 0x05:  // NULL
            return .null
        case 0x80:  // noSuchObject
            return .noSuchObject
        case 0x81:  // noSuchInstance
            return .noSuchInstance
        default:
            return .unknown
        }
    }

    private static func decodeUInt32(_ bytes: [UInt8]) -> UInt32 {
        var v: UInt32 = 0
        for b in bytes.prefix(4) { v = (v << 8) | UInt32(b) }
        return v
    }
}

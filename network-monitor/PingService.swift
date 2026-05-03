import Foundation
import Darwin

struct PingResult {
    let isReachable: Bool
    let responseTimeMs: Double?
}

struct PingService {
    nonisolated func ping(host: String, timeoutSeconds: Int = 3) async -> PingResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = Self.performPing(host: host, timeoutSeconds: timeoutSeconds)
                continuation.resume(returning: result)
            }
        }
    }

    private static func performPing(host: String, timeoutSeconds: Int) -> PingResult {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let res else {
            return PingResult(isReachable: false, responseTimeMs: nil)
        }
        defer { freeaddrinfo(res) }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard sock >= 0 else {
            return fallbackTCPCheck(host: host, timeoutSeconds: timeoutSeconds)
        }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 1...UInt16.max)
        var packet = buildPacket(identifier: identifier, sequence: 1)

        let start = Date()

        let sent = withUnsafeBytes(of: &packet) { ptr in
            sendto(sock, ptr.baseAddress!, MemoryLayout<ICMPPacket>.size, 0,
                   res.pointee.ai_addr, res.pointee.ai_addrlen)
        }
        guard sent > 0 else {
            return PingResult(isReachable: false, responseTimeMs: nil)
        }

        var buffer = [UInt8](repeating: 0, count: 256)
        let received = recv(sock, &buffer, buffer.count, 0)
        guard received > 0 else {
            return PingResult(isReachable: false, responseTimeMs: nil)
        }

        let elapsed = Date().timeIntervalSince(start) * 1000
        return PingResult(isReachable: true, responseTimeMs: elapsed)
    }

    // TCP fallback when ICMP socket is unavailable (sandboxed environment)
    private static func fallbackTCPCheck(host: String, timeoutSeconds: Int) -> PingResult {
        let commonPorts: [Int32] = [80, 443, 22, 8080]
        for port in commonPorts {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, String(port), &hints, &res) == 0, let res else { continue }
            defer { freeaddrinfo(res) }

            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }
            defer { Darwin.close(sock) }

            var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            let start = Date()
            let result = connect(sock, res.pointee.ai_addr, res.pointee.ai_addrlen)
            if result == 0 {
                let elapsed = Date().timeIntervalSince(start) * 1000
                return PingResult(isReachable: true, responseTimeMs: elapsed)
            }
        }
        return PingResult(isReachable: false, responseTimeMs: nil)
    }

    private struct ICMPPacket {
        var type: UInt8
        var code: UInt8
        var checksum: UInt16
        var identifier: UInt16
        var sequence: UInt16
    }

    private static func buildPacket(identifier: UInt16, sequence: UInt16) -> ICMPPacket {
        var pkt = ICMPPacket(
            type: 8, code: 0, checksum: 0,
            identifier: identifier.bigEndian,
            sequence: sequence.bigEndian
        )
        pkt.checksum = checksum(for: &pkt)
        return pkt
    }

    private static func checksum(for packet: inout ICMPPacket) -> UInt16 {
        var sum: UInt32 = 0
        withUnsafeBytes(of: packet) { ptr in
            let words = ptr.bindMemory(to: UInt16.self)
            for word in words { sum += UInt32(word) }
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}

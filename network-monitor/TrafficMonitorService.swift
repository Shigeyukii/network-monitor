import Foundation
import SwiftData

// Counter32 のラップ境界値
private let counter32Max: UInt64 = 0xFFFF_FFFF

@MainActor
struct TrafficMonitorService {
    private let snmp = SNMPService()

    // OID テンプレート
    private static func ifInOID(_ ifIndex: Int)  -> String { "1.3.6.1.2.1.2.2.1.10.\(ifIndex)" }
    private static func ifOutOID(_ ifIndex: Int) -> String { "1.3.6.1.2.1.2.2.1.16.\(ifIndex)" }

    // MARK: - Poll

    func poll(device: Device, config: SNMPConfig, context: ModelContext) async {
        guard config.isEnabled else { return }

        let inOID  = Self.ifInOID(config.interfaceIndex)
        let outOID = Self.ifOutOID(config.interfaceIndex)

        do {
            let result = try await snmp.get(
                host: device.ipAddress,
                community: config.community,
                oids: [inOID, outOID],
                version: config.version
            )

            guard let inOctets  = result[inOID]?.asUInt64,
                  let outOctets = result[outOID]?.asUInt64 else { return }

            let now = Date()
            let newRecord = TrafficRecord(
                inOctets: inOctets,
                outOctets: outOctets,
                device: device
            )

            // 直前のレコードから帯域幅を計算
            if let prev = device.trafficRecords
                .filter({ $0.timestamp < now })
                .max(by: { $0.timestamp < $1.timestamp }) {

                let dt = now.timeIntervalSince(prev.timestamp)
                if dt > 0 {
                    let inDelta  = counterDelta(new: inOctets,  old: prev.inOctets)
                    let outDelta = counterDelta(new: outOctets, old: prev.outOctets)
                    newRecord.inBitsPerSec  = Double(inDelta)  * 8 / dt
                    newRecord.outBitsPerSec = Double(outDelta) * 8 / dt
                }
            }

            context.insert(newRecord)
            try? context.save()

        } catch {
            // SNMP 失敗は致命的ではない（ping と独立）
        }
    }

    // MARK: - Helpers

    /// Counter32 のラップを考慮したデルタ計算
    private func counterDelta(new: UInt64, old: UInt64) -> UInt64 {
        if new >= old {
            return new - old
        }
        // カウンターがラップした場合
        return (counter32Max - old) + new + 1
    }
}

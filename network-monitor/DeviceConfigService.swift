import Foundation
import SwiftData

// MARK: - Codable 構造体

struct DeviceExport: Codable {
    struct TCPPortData: Codable {
        var port: Int
        var label: String
    }
    struct SNMPData: Codable {
        var community: String
        var version: Int
        var interfaceIndex: Int
    }
    struct DeviceData: Codable {
        var name: String
        var ipAddress: String
        var groupName: String
        var isMonitored: Bool
        var tcpPorts: [TCPPortData]
        var snmpConfig: SNMPData?
    }

    var exportedAt: Date
    var schemaVersion: Int
    var devices: [DeviceData]
}

// MARK: - Service

enum DeviceConfigService {

    // MARK: Export

    static func exportData(devices: [Device]) throws -> Data {
        let payload = DeviceExport(
            exportedAt: Date(),
            schemaVersion: 1,
            devices: devices.map { device in
                DeviceExport.DeviceData(
                    name: device.name,
                    ipAddress: device.ipAddress,
                    groupName: device.groupName,
                    isMonitored: device.isMonitored,
                    tcpPorts: device.tcpPorts.map {
                        DeviceExport.TCPPortData(port: $0.port, label: $0.label)
                    },
                    snmpConfig: device.snmpConfig.map {
                        DeviceExport.SNMPData(
                            community: $0.community,
                            version: $0.version,
                            interfaceIndex: $0.interfaceIndex
                        )
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func exportFileURL(devices: [Device]) -> URL? {
        guard let data = try? exportData(devices: devices) else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        let name = "network-monitor-\(fmt.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    // MARK: Import

    @discardableResult
    static func importData(_ data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DeviceExport.self, from: data)

        for d in payload.devices {
            let device = Device(
                name: d.name,
                ipAddress: d.ipAddress,
                groupName: d.groupName,
                isMonitored: d.isMonitored
            )
            context.insert(device)

            for p in d.tcpPorts {
                context.insert(TCPPort(port: p.port, label: p.label, device: device))
            }

            if let s = d.snmpConfig {
                let cfg = SNMPConfig(community: s.community,
                                     version: s.version,
                                     interfaceIndex: s.interfaceIndex)
                device.snmpConfig = cfg
                context.insert(cfg)
            }
        }
        try context.save()
        return payload.devices.count
    }
}

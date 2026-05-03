import Foundation

struct DeviceReport: Identifiable {
    let id: UUID
    let deviceName: String
    let ipAddress: String
    let groupName: String
    let uptimePercent: Double
    let upCount: Int
    let downCount: Int
    let totalCount: Int
    let avgResponseTimeMs: Double?
    let lastChecked: Date?
}

struct UptimeReportService {
    enum TimeRange: String, CaseIterable, Identifiable {
        case oneHour   = "1時間"
        case oneDay    = "24時間"
        case sevenDays = "7日間"
        case thirtyDays = "30日間"

        var id: String { rawValue }

        var interval: TimeInterval {
            switch self {
            case .oneHour:    return 3_600
            case .oneDay:     return 86_400
            case .sevenDays:  return 7 * 86_400
            case .thirtyDays: return 30 * 86_400
            }
        }

        var filenameLabel: String {
            switch self {
            case .oneHour:    return "1h"
            case .oneDay:     return "24h"
            case .sevenDays:  return "7d"
            case .thirtyDays: return "30d"
            }
        }
    }

    func generateReport(devices: [Device], timeRange: TimeRange) -> [DeviceReport] {
        let cutoff = Date().addingTimeInterval(-timeRange.interval)
        return devices
            .map { device in buildReport(device: device, cutoff: cutoff) }
            .sorted { $0.uptimePercent < $1.uptimePercent } // 稼働率の低い順
    }

    private func buildReport(device: Device, cutoff: Date) -> DeviceReport {
        let records = device.pingRecords.filter { $0.timestamp > cutoff }
        let upRecords = records.filter { $0.isReachable }
        let responseTimes = upRecords.compactMap { $0.responseTimeMs }
        let avgMs: Double? = responseTimes.isEmpty ? nil
            : responseTimes.reduce(0, +) / Double(responseTimes.count)
        let uptimePercent = records.isEmpty ? 0.0
            : Double(upRecords.count) / Double(records.count) * 100
        let lastChecked = records.max { $0.timestamp < $1.timestamp }?.timestamp

        return DeviceReport(
            id: device.id,
            deviceName: device.name,
            ipAddress: device.ipAddress,
            groupName: device.groupName,
            uptimePercent: uptimePercent,
            upCount: upRecords.count,
            downCount: records.count - upRecords.count,
            totalCount: records.count,
            avgResponseTimeMs: avgMs,
            lastChecked: lastChecked
        )
    }

    func generateCSV(reports: [DeviceReport], timeRange: TimeRange) -> String {
        let header = "デバイス名,IPアドレス,グループ,稼働率(%),UP回数,DOWN回数,合計チェック数,平均応答時間(ms),最終確認"
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current

        let rows = reports.map { r in
            let avg = r.avgResponseTimeMs.map { String(format: "%.1f", $0) } ?? "-"
            let last = r.lastChecked.map { formatter.string(from: $0) } ?? "-"
            let group = r.groupName.isEmpty ? "-" : r.groupName
            return [
                csvEscape(r.deviceName),
                r.ipAddress,
                csvEscape(group),
                String(format: "%.1f", r.uptimePercent),
                "\(r.upCount)",
                "\(r.downCount)",
                "\(r.totalCount)",
                avg,
                last
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    func csvFileURL(reports: [DeviceReport], timeRange: TimeRange) -> URL? {
        let csv = generateCSV(reports: reports, timeRange: timeRange)
        let date = DateFormatter()
        date.dateFormat = "yyyyMMdd-HHmm"
        let name = "network-report-\(timeRange.filenameLabel)-\(date.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

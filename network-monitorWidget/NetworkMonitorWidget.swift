import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NetworkStatusEntry: TimelineEntry {
    let date: Date
    let devices: [SharedDeviceStatus]

    var upCount: Int   { devices.filter { $0.isUp == true  }.count }
    var downCount: Int { devices.filter { $0.isUp == false }.count }
    var totalCount: Int { devices.count }

    var overallColor: Color {
        if totalCount == 0    { return .gray }
        if downCount == 0     { return .green }
        if upCount == 0       { return .red }
        return .yellow
    }
}

// MARK: - Timeline Provider

struct NetworkMonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetworkStatusEntry {
        NetworkStatusEntry(date: Date(), devices: [
            SharedDeviceStatus(id: UUID(), name: "Router", ipAddress: "192.168.1.1",
                               groupName: "", isUp: true, responseTimeMs: 1.2, lastChecked: Date()),
            SharedDeviceStatus(id: UUID(), name: "Server", ipAddress: "192.168.1.10",
                               groupName: "", isUp: false, responseTimeMs: nil, lastChecked: Date()),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkStatusEntry) -> Void) {
        completion(NetworkStatusEntry(date: Date(), devices: SharedDataService.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkStatusEntry>) -> Void) {
        let entry = NetworkStatusEntry(date: Date(), devices: SharedDataService.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget Views

struct NetworkMonitorWidgetEntryView: View {
    var entry: NetworkMonitorProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// Small: 全体ステータスのみ
struct SmallWidgetView: View {
    var entry: NetworkStatusEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .foregroundStyle(entry.overallColor)
                Text("Network")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }

            if entry.totalCount == 0 {
                Text("未設定")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            } else {
                Text("\(entry.upCount)/\(entry.totalCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(entry.overallColor)
                Text("UP")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// Medium: 上位4デバイスをリスト表示
struct MediumWidgetView: View {
    var entry: NetworkStatusEntry

    private var displayDevices: [SharedDeviceStatus] {
        // DOWN が先に来るよう並べ替え
        let sorted = entry.devices.sorted { a, b in
            let aUp = a.isUp ?? true
            let bUp = b.isUp ?? true
            return !aUp && bUp
        }
        return Array(sorted.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Label("Network Monitor", systemImage: "network")
                    .font(.caption.bold())
                Spacer()
                Text("\(entry.upCount)/\(entry.totalCount) UP")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(entry.overallColor)
            }
            .padding(.bottom, 6)

            if displayDevices.isEmpty {
                Spacer()
                Text("デバイスなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(displayDevices) { device in
                    DeviceWidgetRow(device: device)
                        .padding(.vertical, 2)
                }
                if entry.devices.count > 4 {
                    Text("他 \(entry.devices.count - 4) 台...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
            Text("更新: \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// Large: 上位8デバイス
struct LargeWidgetView: View {
    var entry: NetworkStatusEntry

    private var displayDevices: [SharedDeviceStatus] {
        let sorted = entry.devices.sorted { a, b in
            let aUp = a.isUp ?? true
            let bUp = b.isUp ?? true
            return !aUp && bUp
        }
        return Array(sorted.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Network Monitor", systemImage: "network")
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 8) {
                    Label("\(entry.upCount)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("\(entry.downCount)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(entry.downCount > 0 ? .red : .secondary)
                }
                .font(.caption.monospacedDigit())
            }

            Divider()

            if displayDevices.isEmpty {
                Spacer()
                Text("デバイスなし").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(displayDevices) { device in
                    DeviceWidgetRow(device: device)
                        .padding(.vertical, 3)
                    if device.id != displayDevices.last?.id { Divider() }
                }
                if entry.devices.count > 8 {
                    Text("他 \(entry.devices.count - 8) 台...")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
            Text("更新: \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.quaternary)
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// 共通デバイス行
struct DeviceWidgetRow: View {
    var device: SharedDeviceStatus

    private var statusColor: Color {
        guard let isUp = device.isUp else { return .gray }
        return isUp ? .green : .red
    }

    private var statusLabel: String {
        guard let isUp = device.isUp else { return "?" }
        return isUp ? "UP" : "DOWN"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(device.name)
                .font(.caption)
                .lineLimit(1)

            if !device.groupName.isEmpty {
                Text(device.groupName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let ms = device.responseTimeMs {
                Text(String(format: "%.0fms", ms))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(statusLabel)
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(statusColor)
        }
    }
}

// MARK: - Widget Definition

struct NetworkMonitorWidget: Widget {
    let kind = "NetworkMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkMonitorProvider()) { entry in
            NetworkMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Network Monitor")
        .description("デバイスの死活監視状態を表示します")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

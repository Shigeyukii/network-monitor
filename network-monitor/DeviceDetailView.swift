import SwiftUI
import SwiftData
import Charts

struct DeviceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    var device: Device
    var status: DeviceStatus?

    @State private var showEdit = false
    @State private var showSNMPConfig = false
    @State private var selectedRange: TimeRange = .oneHour

    enum TimeRange: String, CaseIterable {
        case oneHour = "1時間"
        case sixHours = "6時間"
        case oneDay = "24時間"

        var interval: TimeInterval {
            switch self {
            case .oneHour: return 3600
            case .sixHours: return 21600
            case .oneDay: return 86400
            }
        }
    }

    private var filteredPingRecords: [PingRecord] {
        let cutoff = Date().addingTimeInterval(-selectedRange.interval)
        return device.pingRecords
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var recentPingCount: Int {
        let cutoff = Date().addingTimeInterval(-86400)
        return device.pingRecords.filter { $0.timestamp > cutoff }.count
    }

    private var uptimeTintColor: Color {
        let uptime = device.uptimePercentage
        if uptime > 95 { return .green }
        if uptime > 80 { return .yellow }
        return .red
    }

    private var statusLabel: String {
        guard let isUp = status?.isPingUp else { return "確認中..." }
        return isUp ? "UP" : "DOWN"
    }

    var body: some View {
        List {
            statusSection
            uptimeSection
            responseTimeChartSection
            tcpPortsSection
            trafficSection
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("デバイス編集") { showEdit = true }
                    Button("SNMP 設定") { showSNMPConfig = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddDeviceView(device: device)
        }
        .sheet(isPresented: $showSNMPConfig) {
            SNMPConfigSheet(device: device)
        }
    }

    private var trafficSection: some View {
        Section {
            if device.snmpConfig?.isEnabled == true {
                TrafficChartView(device: device)
            } else {
                Button {
                    showSNMPConfig = true
                } label: {
                    Label("SNMP トラフィック監視を設定", systemImage: "waveform.path.ecg")
                }
            }
        } header: {
            HStack {
                Text("トラフィック")
                Spacer()
                if device.snmpConfig?.isEnabled == true {
                    Button {
                        showSNMPConfig = true
                    } label: {
                        Text("設定")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Section("ステータス") {
            HStack {
                StatusDot(isUp: status?.isPingUp)
                VStack(alignment: .leading) {
                    Text(statusLabel)
                        .font(.headline)
                    Text(device.ipAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let ms = status?.pingResponseTimeMs {
                    Text(String(format: "%.1f ms", ms))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let checked = status?.lastChecked {
                LabeledContent("最終確認") {
                    Text(checked, style: .relative) + Text("前")
                }
            }

            if !device.groupName.isEmpty {
                LabeledContent("グループ", value: device.groupName)
            }

            Toggle(isOn: Binding(
                get: { device.isInMaintenance },
                set: { device.isInMaintenance = $0; try? modelContext.save() }
            )) {
                Label("メンテナンスモード", systemImage: "wrench.and.screwdriver.fill")
                    .foregroundStyle(device.isInMaintenance ? .orange : .primary)
            }
        }
    }

    private var uptimeSection: some View {
        let uptime = device.uptimePercentage
        let uptimeText = String(format: "%.1f%%", uptime)
        let countText = "\(recentPingCount) 件のレコード"

        return Section("稼働率（直近24時間）") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(uptimeText)
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: uptime / 100)
                    .tint(uptimeTintColor)
            }
        }
    }

    private var responseTimeChartSection: some View {
        Section {
            Picker("期間", selection: $selectedRange) {
                ForEach(TimeRange.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(.init())
            .listRowBackground(Color.clear)

            PingChartView(records: filteredPingRecords)
        } header: {
            Text("応答時間")
        }
    }

    private var tcpPortsSection: some View {
        Group {
            if !device.tcpPorts.isEmpty {
                Section("TCPポート") {
                    ForEach(device.tcpPorts) { port in
                        TCPPortRow(port: port, isUp: status?.tcpPortStatuses[port.port])
                    }
                }
            }
        }
    }
}

private struct PingChartView: View {
    var records: [PingRecord]

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView("データなし", systemImage: "chart.line.uptrend.xyaxis")
                .frame(height: 140)
        } else {
            Chart {
                ForEach(records) { record in
                    PingChartContent(record: record)
                }
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }
}

private struct PingChartContent: ChartContent {
    var record: PingRecord

    var body: some ChartContent {
        if record.isReachable, let ms = record.responseTimeMs {
            LineMark(
                x: .value("時刻", record.timestamp),
                y: .value("応答時間(ms)", ms)
            )
            .foregroundStyle(Color.blue.gradient)
            PointMark(
                x: .value("時刻", record.timestamp),
                y: .value("応答時間(ms)", ms)
            )
            .foregroundStyle(.blue)
            .symbolSize(20)
        } else {
            PointMark(
                x: .value("時刻", record.timestamp),
                y: .value("応答時間(ms)", 0)
            )
            .foregroundStyle(.red)
            .symbolSize(30)
        }
    }
}

private struct TCPPortRow: View {
    var port: TCPPort
    var isUp: Bool?

    private var statusLabel: String {
        guard let isUp else { return "未確認" }
        return isUp ? "OPEN" : "CLOSED"
    }

    private var statusColor: Color {
        guard let isUp else { return .secondary }
        return isUp ? .green : .red
    }

    private var displayName: String {
        port.label.isEmpty ? "Port \(port.port)" : port.label
    }

    var body: some View {
        HStack {
            StatusDot(isUp: isUp)
            VStack(alignment: .leading) {
                Text(displayName)
                Text(":\(port.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(statusColor)
        }
    }
}

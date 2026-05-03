import SwiftUI
import SwiftData

struct ReportView: View {
    @Query(sort: \Device.name) private var devices: [Device]
    @State private var selectedRange: UptimeReportService.TimeRange = .oneDay
    @State private var reports: [DeviceReport] = []
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false

    private let service = UptimeReportService()

    var body: some View {
        NavigationStack {
            List {
                rangePickerSection
                summarySection
                deviceReportSection
            }
            .navigationTitle("稼働率レポート")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportURL = service.csvFileURL(reports: reports, timeRange: selectedRange)
                        showShareSheet = exportURL != nil
                    } label: {
                        Label("エクスポート", systemImage: "square.and.arrow.up")
                    }
                    .disabled(reports.isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
            .onAppear { refreshReports() }
            .onChange(of: selectedRange) { refreshReports() }
            .onChange(of: devices.count) { refreshReports() }
        }
    }

    private var rangePickerSection: some View {
        Section {
            Picker("期間", selection: $selectedRange) {
                ForEach(UptimeReportService.TimeRange.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
        }
    }

    private var summarySection: some View {
        let avgUptime = reports.isEmpty ? 0.0
            : reports.map(\.uptimePercent).reduce(0, +) / Double(reports.count)
        let downDevices = reports.filter { $0.uptimePercent < 100 }.count
        let totalChecks = reports.map(\.totalCount).reduce(0, +)

        return Section {
            HStack(spacing: 12) {
                ReportSummaryCard(
                    value: String(format: "%.1f%%", avgUptime),
                    label: "平均稼働率",
                    color: avgUptime > 95 ? .green : avgUptime > 80 ? .yellow : .red
                )
                ReportSummaryCard(
                    value: "\(downDevices)",
                    label: "障害あり",
                    color: downDevices > 0 ? .red : .secondary
                )
                ReportSummaryCard(
                    value: "\(totalChecks)",
                    label: "総チェック数",
                    color: .blue
                )
            }
        }
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }

    private var deviceReportSection: some View {
        Section("デバイス別") {
            if reports.isEmpty {
                ContentUnavailableView(
                    "データなし",
                    systemImage: "chart.bar",
                    description: Text("デバイスを追加して監視を開始してください")
                )
            } else {
                ForEach(reports) { report in
                    DeviceReportRow(report: report)
                }
            }
        }
    }

    private func refreshReports() {
        reports = service.generateReport(devices: devices, timeRange: selectedRange)
    }
}

private struct DeviceReportRow: View {
    var report: DeviceReport

    private var uptimeColor: Color {
        if report.uptimePercent > 95 { return .green }
        if report.uptimePercent > 80 { return .yellow }
        return .red
    }

    private var uptimeText: String {
        report.totalCount == 0 ? "データなし" : String(format: "%.1f%%", report.uptimePercent)
    }

    private var avgResponseText: String {
        report.avgResponseTimeMs.map { String(format: "%.1f ms", $0) } ?? "-"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.deviceName)
                        .font(.headline)
                    Text(report.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(uptimeText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(report.totalCount == 0 ? .secondary : uptimeColor)
                    Text(avgResponseText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if report.totalCount > 0 {
                ProgressView(value: report.uptimePercent / 100)
                    .tint(uptimeColor)

                HStack {
                    Label("\(report.upCount) UP", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Label("\(report.downCount) DOWN", systemImage: "xmark.circle.fill")
                        .foregroundStyle(report.downCount > 0 ? .red : .secondary)
                    Spacer()
                    Text("\(report.totalCount) 回")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReportSummaryCard: View {
    var value: String
    var label: String
    var color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// UIActivityViewController ラッパー
private struct ShareSheet: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import SwiftUI
import Charts

struct TrafficChartView: View {
    var device: Device

    @State private var selectedRange: TimeRange = .oneHour

    enum TimeRange: String, CaseIterable {
        case oneHour   = "1時間"
        case sixHours  = "6時間"
        case oneDay    = "24時間"

        var interval: TimeInterval {
            switch self {
            case .oneHour:  return 3_600
            case .sixHours: return 21_600
            case .oneDay:   return 86_400
            }
        }
    }

    private var filteredRecords: [TrafficRecord] {
        let cutoff = Date().addingTimeInterval(-selectedRange.interval)
        return device.trafficRecords
            .filter { $0.timestamp > cutoff && ($0.inBitsPerSec != nil || $0.outBitsPerSec != nil) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var latestIn:  Double { filteredRecords.last?.inBitsPerSec  ?? 0 }
    private var latestOut: Double { filteredRecords.last?.outBitsPerSec ?? 0 }
    private var peakIn:    Double { filteredRecords.compactMap(\.inBitsPerSec).max()  ?? 0 }
    private var peakOut:   Double { filteredRecords.compactMap(\.outBitsPerSec).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // サマリーカード
            HStack(spacing: 12) {
                TrafficStatCard(label: "受信",   current: latestIn,  peak: peakIn,  color: .blue)
                TrafficStatCard(label: "送信",   current: latestOut, peak: peakOut, color: .orange)
            }

            // 期間ピッカー
            Picker("期間", selection: $selectedRange) {
                ForEach(TimeRange.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            // グラフ
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    "データなし",
                    systemImage: "waveform.path.ecg",
                    description: Text("SNMP ポーリングが完了するとグラフが表示されます")
                )
                .frame(height: 180)
            } else {
                Chart {
                    ForEach(filteredRecords) { record in
                        TrafficChartContent(record: record)
                    }
                }
                .chartForegroundStyleScale([
                    "受信": Color.blue,
                    "送信": Color.orange
                ])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bps = value.as(Double.self) {
                                Text(TrafficRecord.formatBps(bps))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 180)
            }
        }
    }
}

private struct TrafficChartContent: ChartContent {
    var record: TrafficRecord

    var body: some ChartContent {
        if let inBps = record.inBitsPerSec {
            LineMark(
                x: .value("時刻", record.timestamp),
                y: .value("bps", inBps)
            )
            .foregroundStyle(by: .value("方向", "受信"))
            .interpolationMethod(.catmullRom)
        }
        if let outBps = record.outBitsPerSec {
            LineMark(
                x: .value("時刻", record.timestamp),
                y: .value("bps", outBps)
            )
            .foregroundStyle(by: .value("方向", "送信"))
            .interpolationMethod(.catmullRom)
        }
    }
}

private struct TrafficStatCard: View {
    var label: String
    var current: Double
    var peak: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption.bold())
            }
            Text(TrafficRecord.formatBps(current))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
            Text("最大: \(TrafficRecord.formatBps(peak))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

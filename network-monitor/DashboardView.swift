import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name) private var devices: [Device]
    @State private var monitor = MonitoringService.shared
    @State private var showAddDevice = false
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil

    private var groups: [String] {
        let names = devices.compactMap { $0.groupName.isEmpty ? nil : $0.groupName }
        return Array(Set(names)).sorted()
    }

    private var filteredDevices: [Device] {
        devices.filter { device in
            let matchGroup = selectedGroup == nil || device.groupName == selectedGroup
            let matchSearch = searchText.isEmpty
                || device.name.localizedCaseInsensitiveContains(searchText)
                || device.ipAddress.localizedCaseInsensitiveContains(searchText)
            return matchGroup && matchSearch
        }
    }

    private var upCount: Int {
        filteredDevices.filter { monitor.deviceStatuses[$0.id]?.isPingUp == true }.count
    }

    private var downCount: Int {
        filteredDevices.count - upCount
    }

    private var downCountColor: Color {
        downCount > 0 ? .red : .secondary
    }

    var body: some View {
        List {
            if !groups.isEmpty {
                groupFilterSection
            }
            summarySection
            deviceSection
        }
        .navigationTitle("ネットワーク監視")
        .searchable(text: $searchText, prompt: "デバイスを検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddDevice = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { monitor.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!monitor.isMonitoring)
            }
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceView()
        }
    }

    private var groupFilterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterChip(label: "すべて", isSelected: selectedGroup == nil) {
                        selectedGroup = nil
                    }
                    ForEach(groups, id: \.self) { group in
                        GroupFilterChip(
                            group: group,
                            selectedGroup: $selectedGroup
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                SummaryCard(value: "\(filteredDevices.count)", label: "合計", color: .blue)
                SummaryCard(value: "\(upCount)", label: "UP", color: .green)
                SummaryCard(value: "\(downCount)", label: "DOWN/不明", color: downCountColor)
            }
        }
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }

    private var deviceSection: some View {
        Section("デバイス") {
            if filteredDevices.isEmpty {
                ContentUnavailableView(
                    "デバイスなし",
                    systemImage: "network",
                    description: Text("右上の＋からデバイスを追加してください")
                )
            } else {
                ForEach(filteredDevices) { device in
                    NavigationLink {
                        DeviceDetailView(
                            device: device,
                            status: monitor.deviceStatuses[device.id]
                        )
                    } label: {
                        DeviceRowView(
                            device: device,
                            status: monitor.deviceStatuses[device.id]
                        )
                    }
                }
                .onDelete(perform: deleteDevices)
            }
        }
    }

    private func deleteDevices(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredDevices[index])
        }
        try? modelContext.save()
    }
}

struct DeviceRowView: View {
    var device: Device
    var status: DeviceStatus?

    private var tcpUpCount: Int {
        device.tcpPorts.filter { status?.tcpPortStatuses[$0.port] == true }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(isUp: status?.isPingUp, size: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                deviceSubtitle
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let ms = status?.pingResponseTimeMs {
                    Text(String(format: "%.0f ms", ms))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !device.tcpPorts.isEmpty {
                    Text("TCP \(tcpUpCount)/\(device.tcpPorts.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var deviceSubtitle: some View {
        HStack {
            Text(device.ipAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !device.groupName.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(device.groupName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GroupFilterChip: View {
    var group: String
    @Binding var selectedGroup: String?

    private var isSelected: Bool { selectedGroup == group }

    var body: some View {
        FilterChip(label: group, isSelected: isSelected) {
            selectedGroup = isSelected ? nil : group
        }
    }
}

struct SummaryCard: View {
    var value: String
    var label: String
    var color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FilterChip: View {
    var label: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color(.systemGray5),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

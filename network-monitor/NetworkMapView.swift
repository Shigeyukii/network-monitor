import SwiftUI
import SwiftData

// MARK: - Main View

struct NetworkMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name) private var devices: [Device]
    @Query private var positions: [DevicePosition]
    @Query private var links: [DeviceLink]
    @State private var monitor = MonitoringService.shared
    @State private var selectedDevice: Device? = nil
    @State private var connectingDevice: Device? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                MapBackgroundStars()

                // グループ自動接続線（破線）
                GroupConnectionLinesView(devices: devices, positions: positions, size: geo.size)

                // 手動接続線（実線）
                ManualLinksView(links: links, positions: positions, size: geo.size)

                // デバイス星
                ForEach(devices) { device in
                    if let pos = positions.first(where: { $0.deviceID == device.id }) {
                        DraggableStarView(
                            device: device,
                            status: monitor.deviceStatuses[device.id],
                            position: pos,
                            containerSize: geo.size,
                            starIconSize: starIconSize(for: device),
                            isConnectMode: connectingDevice != nil,
                            isConnectSource: connectingDevice?.id == device.id,
                            isConnected: connectingDevice.map { src in
                                links.contains { $0.connects(src.id, device.id) }
                            } ?? false,
                            onTap: { handleTap(on: device) },
                            onLongPress: { connectingDevice = device },
                            onDragEnd: { nx, ny in
                                pos.normalizedX = nx
                                pos.normalizedY = ny
                                try? modelContext.save()
                            }
                        )
                    }
                }

                // 接続モードのヒントバー
                if let source = connectingDevice {
                    connectHint(sourceName: source.name)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { ensurePositions() }
        .onChange(of: devices.count) { ensurePositions() }
        .sheet(item: $selectedDevice) { device in
            NavigationStack {
                DeviceDetailView(
                    device: device,
                    status: monitor.deviceStatuses[device.id]
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { selectedDevice = nil }
                    }
                }
            }
        }
    }

    // MARK: - Traffic-based Star Sizing

    private func starIconSize(for device: Device) -> CGFloat {
        let latest = device.trafficRecords.max { $0.timestamp < $1.timestamp }
        let totalBps = (latest?.inBitsPerSec ?? 0) + (latest?.outBitsPerSec ?? 0)
        let minSize: CGFloat = 16
        let maxSize: CGFloat = 30
        guard totalBps > 1_000 else { return minSize }
        // 1Kbps → min, 100Mbps → max（対数スケール）
        let t = (log10(totalBps) - log10(1_000)) / (log10(100_000_000) - log10(1_000))
        return minSize + CGFloat(max(0, min(1, t))) * (maxSize - minSize)
    }

    // MARK: - Actions

    private func handleTap(on device: Device) {
        if let source = connectingDevice {
            if source.id != device.id {
                toggleLink(from: source.id, to: device.id)
            }
            connectingDevice = nil
        } else {
            selectedDevice = device
        }
    }

    private func toggleLink(from: UUID, to: UUID) {
        if let existing = links.first(where: { $0.connects(from, to) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(DeviceLink(from: from, to: to))
        }
        try? modelContext.save()
    }

    private func ensurePositions() {
        let existingIDs = Set(positions.map { $0.deviceID })
        var changed = false
        for device in devices where !existingIDs.contains(device.id) {
            modelContext.insert(DevicePosition(deviceID: device.id))
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    // MARK: - Hint Bar

    private func connectHint(sourceName: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "link")
                Text("\(sourceName) の接続先をタップ")
                    .font(.caption)
                Spacer()
                Button("キャンセル") {
                    connectingDevice = nil
                }
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Background Stars

struct MapBackgroundStars: View {
    private static let stars: [(Double, Double, Double)] = (0..<180).map { i in
        let f = Double(i + 1)
        let x = (sin(f * 17.31) + 1) / 2
        let y = (cos(f * 13.71) + 1) / 2
        let r = 0.4 + abs(sin(f * 7.13)) * 1.6
        return (x, y, r)
    }

    var body: some View {
        Canvas { ctx, size in
            for (nx, ny, r) in Self.stars {
                let rect = CGRect(
                    x: nx * size.width - r,
                    y: ny * size.height - r,
                    width: r * 2, height: r * 2
                )
                let opacity = 0.15 + (r - 0.4) / 1.6 * 0.25
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
    }
}

// MARK: - Group Auto Connection Lines（破線）

struct GroupConnectionLinesView: View {
    var devices: [Device]
    var positions: [DevicePosition]
    var size: CGSize

    private var groupedPositions: [[DevicePosition]] {
        let namedDevices = devices.filter { !$0.groupName.isEmpty }
        let grouped = Dictionary(grouping: namedDevices, by: { $0.groupName })
        return grouped.values.compactMap { groupDevices -> [DevicePosition]? in
            guard groupDevices.count > 1 else { return nil }
            return groupDevices.compactMap { d in positions.first { $0.deviceID == d.id } }
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(groupedPositions.enumerated()), id: \.offset) { _, groupPos in
                GroupLinePath(positions: groupPos, size: size)
            }
        }
    }
}

struct GroupLinePath: View {
    var positions: [DevicePosition]
    var size: CGSize

    var body: some View {
        Path { path in
            guard positions.count > 1 else { return }
            for i in 0..<(positions.count - 1) {
                path.move(to: CGPoint(
                    x: positions[i].normalizedX * size.width,
                    y: positions[i].normalizedY * size.height
                ))
                path.addLine(to: CGPoint(
                    x: positions[i + 1].normalizedX * size.width,
                    y: positions[i + 1].normalizedY * size.height
                ))
            }
        }
        .stroke(Color.white.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }
}

// MARK: - Manual Links（実線）

struct ManualLinksView: View {
    var links: [DeviceLink]
    var positions: [DevicePosition]
    var size: CGSize

    var body: some View {
        ZStack {
            ForEach(links) { link in
                if let fromPos = positions.first(where: { $0.deviceID == link.fromDeviceID }),
                   let toPos   = positions.first(where: { $0.deviceID == link.toDeviceID }) {
                    ManualLinkLine(fromPos: fromPos, toPos: toPos, size: size)
                }
            }
        }
    }
}

struct ManualLinkLine: View {
    var fromPos: DevicePosition
    var toPos: DevicePosition
    var size: CGSize

    var body: some View {
        Path { path in
            path.move(to: CGPoint(
                x: fromPos.normalizedX * size.width,
                y: fromPos.normalizedY * size.height
            ))
            path.addLine(to: CGPoint(
                x: toPos.normalizedX * size.width,
                y: toPos.normalizedY * size.height
            ))
        }
        .stroke(
            Color.white.opacity(0.55),
            style: StrokeStyle(lineWidth: 1.5)
        )
    }
}

// MARK: - Draggable Star

struct DraggableStarView: View {
    var device: Device
    var status: DeviceStatus?
    var position: DevicePosition
    var containerSize: CGSize
    var starIconSize: CGFloat = 20
    var isConnectMode: Bool
    var isConnectSource: Bool
    var isConnected: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onDragEnd: (Double, Double) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var longPressFired = false
    @State private var glowScale: Double = 1.0

    private var starColor: Color {
        if device.isInMaintenance { return .orange }
        guard let isUp = status?.isPingUp else { return .gray }
        return isUp ? Color(red: 0.4, green: 0.8, blue: 1.0) : .red
    }
    private var isUp: Bool { status?.isPingUp == true && !device.isInMaintenance }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // 接続モード: 接続元リング
                if isConnectSource {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(1.1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: isConnectSource)
                }
                // 接続モード: 接続済みリング（緑）
                else if isConnected {
                    Circle()
                        .stroke(Color.green.opacity(0.8), lineWidth: 2)
                        .frame(width: 44, height: 44)
                }
                // 接続モード: 接続可能リング（薄い白）
                else if isConnectMode {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: 40, height: 40)
                }

                // 外側グロー（UP時）
                if isUp {
                    Circle()
                        .fill(starColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .scaleEffect(glowScale)
                }
                // 中間グロー
                Circle()
                    .fill(starColor.opacity(0.3))
                    .frame(width: 28, height: 28)
                // 星アイコン（メンテナンス中はレンチ）
                Image(systemName: device.isInMaintenance
                      ? "wrench.and.screwdriver.fill" : "star.fill")
                    .font(.system(size: starIconSize))
                    .foregroundStyle(starColor)
                    .shadow(color: starColor, radius: isUp ? 4 : 0)
            }

            Text(device.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .lineLimit(1)
                .fixedSize()
        }
        .offset(dragOffset)
        .scaleEffect(isDragging ? 1.15 : (isConnectSource ? 1.1 : 1.0))
        .position(
            x: position.normalizedX * containerSize.width,
            y: position.normalizedY * containerSize.height
        )
        .onLongPressGesture(minimumDuration: 0.5) {
            longPressFired = true
            onLongPress()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !isDragging && dist > 8 { isDragging = true }
                    if isDragging { dragOffset = value.translation }
                }
                .onEnded { value in
                    defer {
                        isDragging = false
                        dragOffset = .zero
                        longPressFired = false
                    }
                    if isDragging {
                        let newX = position.normalizedX + value.translation.width / containerSize.width
                        let newY = position.normalizedY + value.translation.height / containerSize.height
                        onDragEnd(max(0.05, min(0.95, newX)), max(0.05, min(0.95, newY)))
                    } else if !longPressFired {
                        onTap()
                    }
                }
        )
        .onAppear {
            guard isUp else { return }
            let seed = abs(device.id.hashValue) % 100
            let duration = 1.8 + Double(seed) / 100.0 * 1.2
            let delay = Double(seed) / 100.0 * duration
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                glowScale = 1.4
            }
        }
        .animation(.spring(duration: 0.2), value: isDragging)
    }
}

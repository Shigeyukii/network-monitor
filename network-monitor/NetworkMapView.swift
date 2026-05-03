import SwiftUI
import SwiftData

// MARK: - Main View

struct NetworkMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name) private var devices: [Device]
    @Query private var positions: [DevicePosition]
    @State private var monitor = MonitoringService.shared
    @State private var selectedDevice: Device? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                MapBackgroundStars()
                ConnectionLinesView(devices: devices, positions: positions, size: geo.size)

                ForEach(devices) { device in
                    if let pos = positions.first(where: { $0.deviceID == device.id }) {
                        DraggableStarView(
                            device: device,
                            status: monitor.deviceStatuses[device.id],
                            position: pos,
                            containerSize: geo.size,
                            onTap: { selectedDevice = device },
                            onDragEnd: { nx, ny in
                                pos.normalizedX = nx
                                pos.normalizedY = ny
                                try? modelContext.save()
                            }
                        )
                    }
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

    private func ensurePositions() {
        let existingIDs = Set(positions.map { $0.deviceID })
        var changed = false
        for device in devices where !existingIDs.contains(device.id) {
            modelContext.insert(DevicePosition(deviceID: device.id))
            changed = true
        }
        if changed { try? modelContext.save() }
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

// MARK: - Connection Lines

struct ConnectionLinesView: View {
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
                let from = CGPoint(
                    x: positions[i].normalizedX * size.width,
                    y: positions[i].normalizedY * size.height
                )
                let to = CGPoint(
                    x: positions[i + 1].normalizedX * size.width,
                    y: positions[i + 1].normalizedY * size.height
                )
                path.move(to: from)
                path.addLine(to: to)
            }
        }
        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    }
}

// MARK: - Draggable Star

struct DraggableStarView: View {
    var device: Device
    var status: DeviceStatus?
    var position: DevicePosition
    var containerSize: CGSize
    var onTap: () -> Void
    var onDragEnd: (Double, Double) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var glowScale: Double = 1.0

    private var starColor: Color {
        guard let isUp = status?.isPingUp else { return .gray }
        return isUp ? Color(red: 0.4, green: 0.8, blue: 1.0) : .red
    }

    private var isUp: Bool { status?.isPingUp == true }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // 外側グロー
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

                // 星アイコン
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(starColor)
                    .shadow(color: starColor, radius: isUp ? 4 : 0)
            }

            // デバイス名
            Text(device.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .lineLimit(1)
                .fixedSize()
        }
        .offset(dragOffset)
        .scaleEffect(isDragging ? 1.15 : 1.0)
        .position(
            x: position.normalizedX * containerSize.width,
            y: position.normalizedY * containerSize.height
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !isDragging && dist > 8 {
                        isDragging = true
                    }
                    if isDragging {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if isDragging {
                        let newX = position.normalizedX + value.translation.width / containerSize.width
                        let newY = position.normalizedY + value.translation.height / containerSize.height
                        onDragEnd(
                            max(0.05, min(0.95, newX)),
                            max(0.05, min(0.95, newY))
                        )
                    } else {
                        onTap()
                    }
                    isDragging = false
                    dragOffset = .zero
                }
        )
        .onAppear {
            guard isUp else { return }
            // デバイスごとに異なるアニメーション周期でグロー
            let seed = abs(device.id.hashValue) % 100
            let duration = 1.8 + Double(seed) / 100.0 * 1.2
            let delay = Double(seed) / 100.0 * duration
            withAnimation(
                .easeInOut(duration: duration)
                .repeatForever(autoreverses: true)
                .delay(delay)
            ) {
                glowScale = 1.4
            }
        }
        .animation(.spring(duration: 0.2), value: isDragging)
    }
}

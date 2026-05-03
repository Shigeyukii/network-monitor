import Foundation
import SwiftData
import Observation
import WidgetKit

struct DeviceStatus {
    var isPingUp: Bool?
    var pingResponseTimeMs: Double?
    var lastChecked: Date?
    var tcpPortStatuses: [Int: Bool] = [:]
}

@Observable
@MainActor
final class MonitoringService {
    static let shared = MonitoringService()

    var deviceStatuses: [UUID: DeviceStatus] = [:]
    var isMonitoring = false

    private var timer: Timer?
    private var modelContext: ModelContext?
    private let pingService = PingService()
    private let tcpService = TCPService()
    private let alertService = AlertService.shared
    private let settings = AppSettings.shared

    private init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !isMonitoring else { return }
        isMonitoring = true
        scheduleTimer()
        Task { await checkAllDevices() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func refresh() {
        Task { await checkAllDevices() }
    }

    func runSinglePass(modelContext: ModelContext) async {
        self.modelContext = modelContext
        await checkAllDevices()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = Double(settings.pingIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAllDevices() }
        }
    }

    private func checkAllDevices() async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Device>(predicate: #Predicate { $0.isMonitored })
        guard let devices = try? context.fetch(descriptor) else { return }

        await withTaskGroup(of: Void.self) { group in
            for device in devices {
                let deviceID = device.id
                let ip = device.ipAddress
                let name = device.name
                let ports = device.tcpPorts
                group.addTask { [self] in
                    await self.checkDevice(
                        id: deviceID, name: name, ip: ip,
                        ports: ports, device: device, context: context
                    )
                }
            }
        }

        pruneOldRecords(context: context)
        try? context.save()

        // ウィジェット用に最新ステータスを共有 UserDefaults へ書き込む
        let sharedStatuses = devices.map { device in
            SharedDeviceStatus(
                id: device.id,
                name: device.name,
                ipAddress: device.ipAddress,
                groupName: device.groupName,
                isUp: deviceStatuses[device.id]?.isPingUp,
                responseTimeMs: deviceStatuses[device.id]?.pingResponseTimeMs,
                lastChecked: deviceStatuses[device.id]?.lastChecked
            )
        }
        SharedDataService.save(sharedStatuses)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func checkDevice(
        id: UUID, name: String, ip: String,
        ports: [TCPPort], device: Device,
        context: ModelContext
    ) async {
        let prevStatus = deviceStatuses[id]

        let pingResult = await pingService.ping(host: ip)

        var tcpResults: [(TCPPort, Bool)] = []
        for port in ports {
            let ok = await tcpService.check(host: ip, port: port.port)
            tcpResults.append((port, ok))
        }

        context.insert(PingRecord(
            isReachable: pingResult.isReachable,
            responseTimeMs: pingResult.responseTimeMs,
            device: device
        ))
        for (tcpPort, isReachable) in tcpResults {
            context.insert(TCPRecord(isReachable: isReachable, tcpPort: tcpPort))
        }

        var tcpStatuses: [Int: Bool] = [:]
        for (port, ok) in tcpResults { tcpStatuses[port.port] = ok }

        let newStatus = DeviceStatus(
            isPingUp: pingResult.isReachable,
            pingResponseTimeMs: pingResult.responseTimeMs,
            lastChecked: Date(),
            tcpPortStatuses: tcpStatuses
        )
        deviceStatuses[id] = newStatus

        if let prev = prevStatus?.isPingUp, prev != pingResult.isReachable {
            await alertService.sendAlert(deviceName: name, ipAddress: ip, isUp: pingResult.isReachable)
        }
    }

    private func pruneOldRecords(context: ModelContext) {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        let pingDesc = FetchDescriptor<PingRecord>(predicate: #Predicate { $0.timestamp < cutoff })
        let tcpDesc  = FetchDescriptor<TCPRecord>(predicate: #Predicate { $0.timestamp < cutoff })
        (try? context.fetch(pingDesc))?.forEach { context.delete($0) }
        (try? context.fetch(tcpDesc))?.forEach  { context.delete($0) }
    }
}

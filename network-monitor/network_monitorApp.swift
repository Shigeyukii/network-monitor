import SwiftUI
import SwiftData

@main
struct network_monitorApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Device.self,
            PingRecord.self,
            TCPPort.self,
            TCPRecord.self,
            DevicePosition.self,
            SNMPConfig.self,
            TrafficRecord.self,
            DeviceLink.self,
            TrapRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer の作成に失敗しました: \(error)")
        }
    }()

    init() {
        BackgroundMonitoringService.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await NotificationService.shared.requestPermission()
                    BackgroundMonitoringService.scheduleNextRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

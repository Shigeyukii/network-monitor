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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer の作成に失敗しました: \(error)")
        }
    }()

    init() {
        // BGTaskScheduler の登録は init() で行う必要がある
        BackgroundMonitoringService.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 通知許可をリクエスト
                    await NotificationService.shared.requestPermission()
                    // 次回バックグラウンド実行を予約
                    BackgroundMonitoringService.scheduleNextRefresh()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

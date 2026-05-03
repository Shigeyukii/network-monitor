import BackgroundTasks
import SwiftData

enum BackgroundMonitoringService {
    static let refreshIdentifier = "starmanblog.net.network-monitor.refresh"

    /// アプリ起動時に一度だけ呼ぶ
    static func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await handleRefresh(task: refreshTask)
            }
        }
    }

    /// 次回のバックグラウンド実行を予約する
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        // 監視間隔の倍の間隔でバックグラウンドチェックをリクエスト（最短15分）
        let interval = max(15 * 60, Double(AppSettings.shared.pingIntervalSeconds) * 2)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handleRefresh(task: BGAppRefreshTask) async {
        // 次回を予約してから実行
        scheduleNextRefresh()

        let schema = Schema([Device.self, PingRecord.self, TCPPort.self, TCPRecord.self])
        guard let container = try? ModelContainer(for: schema) else {
            task.setTaskCompleted(success: false)
            return
        }
        let context = ModelContext(container)

        var expired = false
        task.expirationHandler = {
            expired = true
            task.setTaskCompleted(success: false)
        }

        await MonitoringService.shared.runSinglePass(modelContext: context)

        if !expired {
            task.setTaskCompleted(success: true)
        }
    }
}

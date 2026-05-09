import UserNotifications

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        UNUserNotificationCenter.current().delegate = self
    }

    func sendTrapAlert(sourceIP: String, trapName: String) {
        let content = UNMutableNotificationContent()
        content.title = "SNMP トラップ受信"
        content.body = "\(sourceIP) から \(trapName)"
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: "trap-\(sourceIP)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendAlert(deviceName: String, isUp: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isUp ? "回復" : "障害発生"
        content.body = "\(deviceName) が\(isUp ? "回復" : "ダウン")しました"
        content.sound = .default
        content.interruptionLevel = isUp ? .active : .timeSensitive

        let request = UNNotificationRequest(
            identifier: "alert-\(deviceName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    // フォアグラウンド中でも通知を表示する
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

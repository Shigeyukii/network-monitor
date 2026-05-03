import Foundation

struct AlertService {
    static let shared = AlertService()
    private let settings = AppSettings.shared

    nonisolated func sendAlert(deviceName: String, ipAddress: String, isUp: Bool) async {
        // ローカル通知（アプリがバックグラウンドでも届く）
        await MainActor.run {
            NotificationService.shared.sendAlert(deviceName: deviceName, isUp: isUp)
        }

        guard settings.alertEnabled else { return }

        let emoji = isUp ? "✅" : "🔴"
        let status = isUp ? "回復" : "障害発生"
        let message = "\(emoji) [\(status)] \(deviceName) (\(ipAddress)) が\(status)しました"

        let teams = settings.teamsWebhookURL
        let slack = settings.slackWebhookURL

        async let _ = sendToTeams(webhookURL: teams, message: message)
        async let _ = sendToSlack(webhookURL: slack, message: message)
    }

    private func sendToTeams(webhookURL: String, message: String) async {
        guard !webhookURL.isEmpty, let url = URL(string: webhookURL) else { return }
        await postJSON(url: url, body: ["text": message])
    }

    private func sendToSlack(webhookURL: String, message: String) async {
        guard !webhookURL.isEmpty, let url = URL(string: webhookURL) else { return }
        await postJSON(url: url, body: ["text": message])
    }

    private func postJSON(url: URL, body: [String: String]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
}

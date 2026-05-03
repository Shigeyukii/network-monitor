import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var pingIntervalSeconds: Int {
        get { max(10, UserDefaults.standard.integer(forKey: "pingInterval").nonZeroOr(30)) }
        set { UserDefaults.standard.set(newValue, forKey: "pingInterval") }
    }

    var teamsWebhookURL: String {
        get { UserDefaults.standard.string(forKey: "teamsWebhook") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "teamsWebhook") }
    }

    var slackWebhookURL: String {
        get { UserDefaults.standard.string(forKey: "slackWebhook") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "slackWebhook") }
    }

    var alertEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "alertEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "alertEnabled") }
    }

    private init() {}
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

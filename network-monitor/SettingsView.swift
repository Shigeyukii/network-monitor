import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var intervalValue: Double = Double(AppSettings.shared.pingIntervalSeconds)

    var body: some View {
        NavigationStack {
            Form {
                Section("監視設定") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("チェック間隔")
                            Spacer()
                            Text("\(Int(intervalValue))秒")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $intervalValue, in: 10...300, step: 10) {
                            Text("間隔")
                        } minimumValueLabel: {
                            Text("10s")
                        } maximumValueLabel: {
                            Text("5m")
                        }
                        .onChange(of: intervalValue) { _, new in
                            settings.pingIntervalSeconds = Int(new)
                        }
                    }
                }

                Section("アラート") {
                    Toggle("アラートを有効化", isOn: $settings.alertEnabled)

                    LabeledContent("Microsoft Teams") {
                        TextField("Webhook URL", text: $settings.teamsWebhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Slack") {
                        TextField("Webhook URL", text: $settings.slackWebhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("データ保持") {
                    LabeledContent("Ping履歴", value: "7日間")
                    LabeledContent("TCP履歴", value: "7日間")
                }

                Section("アプリ情報") {
                    LabeledContent("バージョン", value: "1.0.0")
                }
            }
            .navigationTitle("設定")
        }
    }
}

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name) private var devices: [Device]
    @State private var settings = AppSettings.shared
    @State private var intervalValue: Double = Double(AppSettings.shared.pingIntervalSeconds)
    @State private var showImportPicker = false
    @State private var exportURL: URL? = nil
    @State private var showExportSheet = false
    @State private var importResultMessage: String? = nil
    @State private var showImportResult = false

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

                Section {
                    Button {
                        exportURL = DeviceConfigService.exportFileURL(devices: devices)
                        showExportSheet = exportURL != nil
                    } label: {
                        Label("デバイス設定をエクスポート", systemImage: "square.and.arrow.up")
                    }
                    .disabled(devices.isEmpty)

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("デバイス設定をインポート", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("デバイス設定")
                } footer: {
                    Text("エクスポートしたJSONファイルを使って、デバイス設定を別の端末や同じ端末に復元できます。")
                }

                Section("データ保持") {
                    LabeledContent("Ping履歴", value: "7日間")
                    LabeledContent("TCP履歴", value: "7日間")
                    LabeledContent("トラフィック履歴", value: "7日間")
                }

                Section("アプリ情報") {
                    LabeledContent("バージョン", value: "1.0.0")
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .alert("インポート結果", isPresented: $showImportResult) {
                Button("OK") {}
            } message: {
                Text(importResultMessage ?? "")
            }
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let count = try DeviceConfigService.importData(data, into: modelContext)
                importResultMessage = "\(count) 台のデバイスをインポートしました。"
            } catch {
                importResultMessage = "インポート失敗: \(error.localizedDescription)"
            }
        case .failure(let error):
            importResultMessage = "ファイル選択失敗: \(error.localizedDescription)"
        }
        showImportResult = true
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

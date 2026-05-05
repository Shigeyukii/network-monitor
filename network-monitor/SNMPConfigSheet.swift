import SwiftUI
import SwiftData

struct SNMPConfigSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var device: Device

    @State private var community = "public"
    @State private var version = 1
    @State private var interfaceIndex = 1
    @State private var isEnabled = true
    @State private var testResult: TestResult? = nil
    @State private var isTesting = false

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本設定") {
                    Toggle("SNMP 監視を有効化", isOn: $isEnabled)

                    Picker("バージョン", selection: $version) {
                        Text("v1").tag(0)
                        Text("v2c").tag(1)
                    }

                    LabeledContent("コミュニティ文字列") {
                        TextField("public", text: $community)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }

                    Stepper("インターフェース: \(interfaceIndex)", value: $interfaceIndex, in: 1...64)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text("接続テスト")
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("テスト")
                } footer: {
                    Text("対象デバイスで SNMP が有効になっていること、UDP 161 番ポートへのアクセスが許可されていることを確認してください。")
                }
            }
            .navigationTitle("SNMP 設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(community.isEmpty)
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        guard let config = device.snmpConfig else { return }
        community       = config.community
        version         = config.version
        interfaceIndex  = config.interfaceIndex
        isEnabled       = config.isEnabled
    }

    private func save() {
        if let config = device.snmpConfig {
            config.community      = community
            config.version        = version
            config.interfaceIndex = interfaceIndex
            config.isEnabled      = isEnabled
        } else {
            let config = SNMPConfig(community: community, version: version,
                                    interfaceIndex: interfaceIndex)
            config.isEnabled = isEnabled
            device.snmpConfig = config
            modelContext.insert(config)
        }
        try? modelContext.save()
        dismiss()
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let sysDescrOID = "1.3.6.1.2.1.1.1.0"
        let service = SNMPService()
        do {
            let result = try await service.get(
                host: device.ipAddress,
                community: community,
                oids: [sysDescrOID],
                version: version,
                timeoutSeconds: 3
            )
            if let value = result[sysDescrOID],
               case .octetString(let data) = value,
               let desc = String(data: data, encoding: .utf8) {
                testResult = .success("OK: \(desc.prefix(60))")
            } else {
                testResult = .success("OK: 応答受信")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }
}

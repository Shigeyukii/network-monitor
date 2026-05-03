import SwiftUI
import SwiftData

struct AddDeviceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var device: Device? = nil

    @State private var name = ""
    @State private var ipAddress = ""
    @State private var groupName = ""
    @State private var tcpPorts: [(port: String, label: String)] = []
    @State private var newPort = ""
    @State private var newPortLabel = ""

    private var isEditing: Bool { device != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("デバイス情報") {
                    TextField("名前", text: $name)
                    TextField("IPアドレス / ホスト名", text: $ipAddress)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("グループ（任意）", text: $groupName)
                }

                Section("TCPポート監視") {
                    ForEach(tcpPorts.indices, id: \.self) { i in
                        HStack {
                            Text(":\(tcpPorts[i].port)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(tcpPorts[i].label.isEmpty ? "—" : tcpPorts[i].label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { tcpPorts.remove(atOffsets: $0) }

                    HStack {
                        TextField("ポート番号", text: $newPort)
                            .keyboardType(.numberPad)
                            .frame(width: 90)
                        TextField("ラベル（例: HTTP）", text: $newPortLabel)
                        Button("追加") { addPort() }
                            .disabled(newPort.isEmpty || Int(newPort) == nil)
                    }
                }
            }
            .navigationTitle(isEditing ? "デバイス編集" : "デバイス追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || ipAddress.isEmpty)
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    private func addPort() {
        guard let _ = Int(newPort) else { return }
        tcpPorts.append((port: newPort, label: newPortLabel))
        newPort = ""
        newPortLabel = ""
    }

    private func populateIfEditing() {
        guard let device else { return }
        name = device.name
        ipAddress = device.ipAddress
        groupName = device.groupName
        tcpPorts = device.tcpPorts.map { (port: String($0.port), label: $0.label) }
    }

    private func save() {
        if let device {
            device.name = name
            device.ipAddress = ipAddress
            device.groupName = groupName

            let existingPorts = device.tcpPorts
            existingPorts.forEach { modelContext.delete($0) }

            for entry in tcpPorts {
                if let portNum = Int(entry.port) {
                    let port = TCPPort(port: portNum, label: entry.label, device: device)
                    modelContext.insert(port)
                }
            }
        } else {
            let newDevice = Device(name: name, ipAddress: ipAddress, groupName: groupName)
            modelContext.insert(newDevice)

            for entry in tcpPorts {
                if let portNum = Int(entry.port) {
                    let port = TCPPort(port: portNum, label: entry.label, device: newDevice)
                    modelContext.insert(port)
                }
            }
        }
        try? modelContext.save()
        dismiss()
    }
}

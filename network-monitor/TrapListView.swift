import SwiftUI
import SwiftData

struct TrapListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrapRecord.timestamp, order: .reverse) private var traps: [TrapRecord]
    @State private var receiver = SNMPTrapReceiver.shared
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                trapListSection
            }
            .navigationTitle("SNMPトラップ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            receiver.markAllRead(context: modelContext)
                        } label: {
                            Label("すべて既読にする", systemImage: "checkmark.circle")
                        }
                        .disabled(receiver.unreadCount == 0)

                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("すべて削除", systemImage: "trash")
                        }
                        .disabled(traps.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("すべてのトラップ履歴を削除しますか？",
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleteAll() }
            }
            .onAppear { syncUnreadCount() }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: receiver.isListening
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(receiver.isListening ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(receiver.isListening
                         ? "受信中 (UDP :\(receiver.listenPort))"
                         : "停止中")
                        .font(.subheadline)
                    if let err = receiver.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Text("\(traps.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trapListSection: some View {
        Section("受信履歴") {
            if traps.isEmpty {
                ContentUnavailableView(
                    "トラップなし",
                    systemImage: "bell.slash",
                    description: Text("デバイスからのSNMPトラップがここに表示されます")
                )
            } else {
                ForEach(traps) { trap in
                    NavigationLink {
                        TrapDetailView(trap: trap)
                            .onAppear {
                                if !trap.isRead {
                                    trap.isRead = true
                                    try? modelContext.save()
                                    receiver.unreadCount = max(0, receiver.unreadCount - 1)
                                }
                            }
                    } label: {
                        TrapRowView(trap: trap)
                    }
                }
                .onDelete { offsets in
                    offsets.map { traps[$0] }.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                    syncUnreadCount()
                }
            }
        }
    }

    // MARK: - Helpers

    private func deleteAll() {
        traps.forEach { modelContext.delete($0) }
        try? modelContext.save()
        receiver.unreadCount = 0
    }

    private func syncUnreadCount() {
        receiver.unreadCount = traps.filter { !$0.isRead }.count
    }
}

// MARK: - Trap Row

struct TrapRowView: View {
    var trap: TrapRecord

    private var iconColor: Color {
        switch trap.trapColor {
        case "green":  return .green
        case "red":    return .red
        case "orange": return .orange
        default:       return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: trap.trapIcon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(trap.trapName)
                        .font(.headline)
                    if !trap.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(trap.sourceIP)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(trap.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("v\(trap.snmpVersion == 1 ? "1" : "2c")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Trap Detail

struct TrapDetailView: View {
    var trap: TrapRecord

    var body: some View {
        List {
            Section("概要") {
                LabeledContent("トラップ種別", value: trap.trapName)
                LabeledContent("送信元 IP",    value: trap.sourceIP)
                LabeledContent("SNMP バージョン", value: trap.snmpVersion == 1 ? "v1" : "v2c")
                LabeledContent("コミュニティ",  value: trap.community)
                LabeledContent("受信日時") {
                    Text(trap.timestamp.formatted(date: .abbreviated, time: .standard))
                }
            }

            Section("OID") {
                Text(trap.trapOID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !trap.varbinds.isEmpty {
                Section("Varbinds") {
                    ForEach(trap.varbinds.sorted(by: { $0.key < $1.key }), id: \.key) { oid, value in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(oid)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("トラップ詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

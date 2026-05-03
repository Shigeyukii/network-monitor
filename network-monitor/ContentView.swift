import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var monitor = MonitoringService.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("ダッシュボード", systemImage: "network")
            }
            .tag(0)

            NavigationStack {
                ReportView()
            }
            .tabItem {
                Label("レポート", systemImage: "chart.bar.doc.horizontal")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gear")
            }
            .tag(2)
        }
        .onAppear {
            monitor.start(modelContext: modelContext)
        }
    }
}

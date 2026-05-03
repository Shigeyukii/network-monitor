import SwiftUI
import SwiftData

enum AppSection: Hashable {
    case dashboard, map, report, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var monitor = MonitoringService.shared
    @State private var selectedSection: AppSection? = .dashboard
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onAppear {
            monitor.start(modelContext: modelContext)
        }
    }

    // MARK: - iPhone (TabView)

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DashboardView() }
                .tabItem { Label("ダッシュボード", systemImage: "network") }
                .tag(0)

            NavigationStack {
                NetworkMapView()
                    .navigationTitle("ネットワークマップ")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Color.black, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
            .tabItem { Label("マップ", systemImage: "star.fill") }
            .tag(1)

            NavigationStack { ReportView() }
                .tabItem { Label("レポート", systemImage: "chart.bar.doc.horizontal") }
                .tag(2)

            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gear") }
                .tag(3)
        }
    }

    // MARK: - iPad (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedSection) {
                Section("監視") {
                    Label("ダッシュボード", systemImage: "network")
                        .tag(AppSection.dashboard)
                    Label("マップ", systemImage: "star.fill")
                        .tag(AppSection.map)
                }
                Section("分析") {
                    Label("レポート", systemImage: "chart.bar.doc.horizontal")
                        .tag(AppSection.report)
                }
                Section("その他") {
                    Label("設定", systemImage: "gear")
                        .tag(AppSection.settings)
                }
            }
            .navigationTitle("Network Monitor")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            iPadDetail
        }
    }

    @ViewBuilder
    private var iPadDetail: some View {
        switch selectedSection ?? .dashboard {
        case .dashboard:
            NavigationStack { DashboardView() }
        case .map:
            NetworkMapView()
                .ignoresSafeArea()
        case .report:
            NavigationStack { ReportView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}

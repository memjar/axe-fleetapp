// AXE Fleet Monitor — Root View (iOS)
// TabView with 4 tabs: Dashboard, Insights, Events, Settings.

import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = FleetMonitor()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(monitor: monitor)
                .tabItem {
                    Label("Fleet", systemImage: "server.rack")
                }
                .tag(0)

            AIInsightsView(monitor: monitor)
                .tabItem {
                    Label("Insights", systemImage: "brain")
                }
                .tag(1)

            EventsView(monitor: monitor)
                .tabItem {
                    Label("Events", systemImage: "list.bullet.clipboard")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(AXETheme.gold)
        .preferredColorScheme(.dark)
        .onAppear {
            configureTabBarAppearance()
            monitor.startPolling()
        }
        .onDisappear {
            monitor.stopPolling()
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AXETheme.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

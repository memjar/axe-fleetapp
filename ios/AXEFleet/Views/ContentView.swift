import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = FleetMonitor()
    @State private var selectedTab = 0
    @State private var activeToasts: [FleetEvent] = []
    @State private var lastSeenEventId: String?
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            // Main tab view
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
                    .badge(monitor.newEventCount)
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
            .tint(AXETheme.gold)
            .preferredColorScheme(.dark)
            
            // Toast notification overlay
            VStack(spacing: 8) {
                ForEach(activeToasts) { toast in
                    EventToastBanner(event: toast)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(.top, 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeToasts.map(\.id))
            .allowsHitTesting(false)
        }
        .onAppear {
            configureTabBarAppearance()
            monitor.startPolling()
            monitor.startEventPolling()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                monitor.startPolling()
                monitor.startEventPolling()
            case .background:
                monitor.stopPolling()
                monitor.stopEventPolling()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onReceive(monitor.$events) { events in
            guard let newest = events.first else { return }
            if newest.id != lastSeenEventId {
                lastSeenEventId = newest.id
                showToast(newest)
            }
        }
        .onChange(of: selectedTab) { _ in
            if selectedTab == 2 {
                monitor.resetNewEventCount()
            }
        }
    }
    
    // MARK: - Toast Management
    
    private func showToast(_ event: FleetEvent) {
        guard !activeToasts.contains(where: { $0.id == event.id }) else { return }
        
        withAnimation {
            activeToasts.insert(event, at: 0)
            // Max 3 visible toasts
            if activeToasts.count > 3 {
                activeToasts = Array(activeToasts.prefix(3))
            }
        }
        
        // Auto-dismiss after 4 seconds
        let eventId = event.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation {
                self.activeToasts.removeAll { $0.id == eventId }
            }
        }
    }
    
    // MARK: - Tab Bar
    
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AXETheme.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

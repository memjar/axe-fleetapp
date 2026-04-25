// AXE Fleet Monitor — Settings (iOS)
// Server connection config, notification prefs, about section.

import SwiftUI

struct SettingsView: View {
    @AppStorage("server_url") private var serverURL = "https://axiom.com.vc/api/fleet"
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("poll_interval") private var pollInterval = 15
    @State private var connectionTestResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            ZStack {
                AXETheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AXETheme.sectionSpacing) {
                        connectionSection
                        notificationSection
                        aboutSection
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(AXETheme.titleFont)
                        .foregroundColor(AXETheme.gold)
                }
            }
            .toolbarBackground(AXETheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SERVER CONNECTION")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.gold)

            VStack(spacing: 8) {
                HStack {
                    Text("Server URL")
                        .font(AXETheme.bodyFont)
                        .foregroundColor(AXETheme.textSecondary)
                    Spacer()
                }
                TextField("https://axiom.com.vc/api/fleet", text: $serverURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AXETheme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(12)
                    .background(AXETheme.surfaceElevated)
                    .cornerRadius(8)
            }

            Button(action: testConnection) {
                HStack {
                    if isTesting {
                        ProgressView()
                            .tint(AXETheme.background)
                            .scaleEffect(0.8)
                    }
                    Text(isTesting ? "TESTING..." : "TEST CONNECTION")
                        .font(AXETheme.headlineFont)
                }
                .foregroundColor(AXETheme.background)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(AXETheme.gold)
                .cornerRadius(AXETheme.cornerRadius)
            }
            .disabled(isTesting)

            if let result = connectionTestResult {
                Text(result)
                    .font(AXETheme.captionFont)
                    .foregroundColor(result.contains("[+]") ? AXETheme.statusUp : AXETheme.statusDown)
            }
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATIONS")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.gold)

            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push Notifications")
                        .font(AXETheme.bodyFont)
                        .foregroundColor(AXETheme.textPrimary)
                    Text("Alert on state changes")
                        .font(AXETheme.captionFont)
                        .foregroundColor(AXETheme.textSecondary)
                }
            }
            .tint(AXETheme.gold)
            .padding(12)
            .background(AXETheme.surfaceElevated)
            .cornerRadius(8)

            HStack {
                Text("Poll Interval")
                    .font(AXETheme.bodyFont)
                    .foregroundColor(AXETheme.textSecondary)
                Spacer()
                Picker("", selection: $pollInterval) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(12)
            .background(AXETheme.surfaceElevated)
            .cornerRadius(8)
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.gold)

            VStack(spacing: 8) {
                aboutRow("Version", value: "1.0.0")
                aboutRow("Backend", value: "axiom.com.vc")
                aboutRow("Architecture", value: "Cloud Native")
                aboutRow("API Spend", value: "$0 — sovereign")
            }

            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("AXE TECHNOLOGIES")
                        .font(AXETheme.captionFont)
                        .foregroundColor(AXETheme.gold)
                    Text("Every wall has a door")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AXETheme.textSecondary)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textSecondary)
            Spacer()
            Text(value)
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textPrimary)
        }
        .padding(12)
        .background(AXETheme.surfaceElevated)
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func testConnection() {
        isTesting = true
        connectionTestResult = nil
        Task {
            await APIClient.shared.updateServer(url: serverURL)
            let reachable = await APIClient.shared.isDaemonReachable()
            await MainActor.run {
                isTesting = false
                connectionTestResult = reachable
                    ? "[+] Connected to \(serverURL)"
                    : "[-] Cannot reach \(serverURL)"
            }
        }
    }
}

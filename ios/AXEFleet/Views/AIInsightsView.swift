// AXE Fleet Monitor — AI Insights (iOS)
// Displays local model fleet analysis and incident reports.
// Powered by Carmack Pattern (axe_sdk → llama-server).

import SwiftUI

struct AIInsightsView: View {
    @ObservedObject var monitor: FleetMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                AXETheme.background.ignoresSafeArea()

                if let summary = monitor.aiSummary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AXETheme.sectionSpacing) {
                            modelStatusBanner(summary)
                            fleetAnalysis(summary)

                            if !summary.incidents.isEmpty {
                                incidentSection(summary.incidents)
                            }

                            Spacer(minLength: 40)
                        }
                        .padding()
                    }
                } else {
                    awaitingView
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AI INSIGHTS")
                        .font(AXETheme.titleFont)
                        .foregroundColor(AXETheme.gold)
                }
            }
            .toolbarBackground(AXETheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Model Status

    private func modelStatusBanner(_ summary: SummaryResponse) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(summary.modelAvailable ? AXETheme.statusUp : AXETheme.statusUnknown)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.modelAvailable ? "LOCAL MODEL ACTIVE" : "FALLBACK MODE")
                    .font(AXETheme.headlineFont)
                    .foregroundColor(AXETheme.textPrimary)
                Text(summary.modelAvailable ? "Carmack Pattern — zero API spend" : "Deterministic analysis — model offline")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
            Spacer()
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - Fleet Analysis

    private func fleetAnalysis(_ summary: SummaryResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("[AI]")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.gold)
                Text("FLEET ANALYSIS")
                    .font(AXETheme.headlineFont)
                    .foregroundColor(AXETheme.gold)
            }

            Text(summary.fleetSummary)
                .font(AXETheme.bodyFont)
                .foregroundColor(AXETheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let generated = summary.lastGenerated {
                Text("Generated: \(generated)")
                    .font(AXETheme.captionFont)
                    .foregroundColor(AXETheme.textSecondary)
            }
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - Incidents

    private func incidentSection(_ incidents: [IncidentEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT INCIDENTS")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.gold)

            ForEach(incidents) { incident in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("[>]")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AXETheme.gold)
                        Text(incident.target.uppercased())
                            .font(AXETheme.headlineFont)
                            .foregroundColor(AXETheme.textPrimary)
                        Spacer()
                        Text(incident.transition)
                            .font(AXETheme.captionFont)
                            .foregroundColor(AXETheme.statusFlapping)
                    }
                    Text(incident.analysis)
                        .font(AXETheme.bodyFont)
                        .foregroundColor(AXETheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(AXETheme.surfaceElevated)
                .cornerRadius(8)
            }
        }
        .padding(AXETheme.cardPadding)
        .background(AXETheme.surface)
        .cornerRadius(AXETheme.cornerRadius)
    }

    // MARK: - Awaiting

    private var awaitingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(AXETheme.textSecondary)
            Text("AWAITING AI ANALYSIS")
                .font(AXETheme.headlineFont)
                .foregroundColor(AXETheme.textSecondary)
            Text("Summary generates every 60 seconds\nwhen connected to fleet daemon")
                .font(AXETheme.captionFont)
                .foregroundColor(AXETheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

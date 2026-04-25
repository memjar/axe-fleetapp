//
//  UpdateService.swift
//  AXEFleet
//
//  Remote update service — checks AXIOM for new versions
//

import Foundation
import SwiftUI

// MARK: - API Response Models

struct AppVersionResponse: Codable {
    let app: String
    let version: String
    let build: Int
    let changelog: String
    let ipa_url: String?
    let manifest_url: String?
    let updated_at: String
}

struct UpdateNotificationResponse: Codable {
    let id: String
    let app: String
    let version: String
    let title: String
    let message: String
    let priority: String
    let action_url: String?
    let created_at: String
    let expires_at: String?
}

struct UpdatesResponse: Codable {
    let updates: [UpdateNotificationResponse]
    let count: Int
    let timestamp: String
}

// MARK: - Update Service

@MainActor
class UpdateService: ObservableObject {
    @Published var updateAvailable = false
    @Published var updateTitle = ""
    @Published var updateMessage = ""
    @Published var updateVersion = ""
    @Published var manifestURL: String?
    @Published var isChecking = false

    private let appName = "AXEFleet"
    private let baseURL = "https://axiom.com.vc/api/apps"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: "\(baseURL)/versions?app=\(appName)") else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let version = try JSONDecoder().decode(AppVersionResponse.self, from: data)

            if isNewer(remote: version.version, remoteBuild: version.build) {
                if let updatesURL = URL(string: "\(baseURL)/updates?app=\(appName)") {
                    let (uData, uResp) = try await URLSession.shared.data(from: updatesURL)
                    if let uHttp = uResp as? HTTPURLResponse, uHttp.statusCode == 200,
                       let updates = try? JSONDecoder().decode(UpdatesResponse.self, from: uData),
                       let latest = updates.updates.first {
                        updateTitle = latest.title
                        updateMessage = latest.message
                        manifestURL = latest.action_url ?? version.manifest_url
                    } else {
                        updateTitle = "Update Available"
                        updateMessage = version.changelog.isEmpty
                            ? "Version \(version.version) is ready to install."
                            : version.changelog
                        manifestURL = version.manifest_url
                    }
                }

                updateVersion = version.version
                withAnimation(.easeInOut(duration: 0.4)) {
                    updateAvailable = true
                }
            } else {
                updateAvailable = false
            }
        } catch {
            // Silent — don't interrupt with network errors
        }
    }

    func installUpdate() {
        guard let manifest = manifestURL else { return }
        var components = URLComponents()
        components.scheme = "itms-services"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifest)
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    func dismissUpdate() {
        withAnimation(.easeOut(duration: 0.3)) {
            updateAvailable = false
        }
    }

    private func isNewer(remote: String, remoteBuild: Int) -> Bool {
        let localParts = currentVersion.split(separator: ".").compactMap { Int($0) }
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(localParts.count, remoteParts.count) {
            let l = i < localParts.count ? localParts[i] : 0
            let r = i < remoteParts.count ? remoteParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }

        return remoteBuild > currentBuild
    }
}

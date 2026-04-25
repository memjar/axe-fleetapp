//
//  UpdateBannerView.swift
//  AXEFleet
//
//  Gold update banner — appears when a new version is available
//

import SwiftUI

struct UpdateBannerView: View {
    @ObservedObject var updateService: UpdateService
    @State private var isExpanded = false

    private let goldLight = Color(red: 232/255, green: 212/255, blue: 139/255)
    private let goldDark = Color(red: 201/255, green: 168/255, blue: 76/255)

    var body: some View {
        if updateService.updateAvailable {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(updateService.updateTitle)
                                .font(.system(size: 14, weight: .semibold))
                            Text("v\(updateService.updateVersion)")
                                .font(.system(size: 11, weight: .medium))
                                .opacity(0.7)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [goldDark, goldLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 12) {
                        Text(updateService.updateMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 12) {
                            Button {
                                updateService.dismissUpdate()
                            } label: {
                                Text("Later")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            Button {
                                updateService.installUpdate()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line")
                                    Text("Install Update")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [goldDark, goldLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

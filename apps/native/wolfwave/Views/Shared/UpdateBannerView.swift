//
//  UpdateBannerView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/17/26.
//

import SwiftUI

// MARK: - Update Banner View

/// In-app banner displayed when a new version of WolfWave is available.
///
/// Shows the available version and provides a button to open the release page.
/// Dismissible by the user. Listens for `updateStateChanged` notifications.
struct UpdateBannerView: View {

    @State private var isUpdateAvailable = false
    @State private var latestVersion = ""
    @State private var releaseURL: URL?
    @State private var isDismissed = false

    var body: some View {
        if isUpdateAvailable && !isDismissed {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("WolfWave v\(latestVersion) is ready to download.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                if let url = releaseURL {
                    Button("Download") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.small)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Modifier that wires up update state listening.
    func listening() -> some View {
        self
            .onAppear {
                // Update state is delivered via NotificationCenter (handled by onReceive below).
                // Sparkle manages its own update checking lifecycle.
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSNotification.Name(AppConstants.Notifications.updateStateChanged)
                )
            ) { notification in
                guard let userInfo = notification.userInfo,
                      let available = userInfo["isUpdateAvailable"] as? Bool,
                      let version = userInfo["latestVersion"] as? String
                else { return }

                if available {
                    latestVersion = version
                    if let urlString = userInfo["releaseURL"] as? String,
                       let url = URL(string: urlString)
                    {
                        releaseURL = url
                    } else {
                        releaseURL = URL(string: AppConstants.URLs.githubReleases)
                    }
                    isUpdateAvailable = true
                    isDismissed = false
                } else {
                    isUpdateAvailable = false
                }
            }
    }
}
// MARK: - Preview

#Preview("Update Available") {
    VStack(spacing: 16) {
        let view = UpdateBannerView()
        view
            .onAppear {
                NotificationCenter.default.post(
                    name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
                    object: nil,
                    userInfo: [
                        "isUpdateAvailable": true,
                        "latestVersion": "1.2.0",
                        "releaseURL": "https://github.com/mrdemonwolf/wolfwave/releases/tag/v1.2.0"
                    ]
                )
            }
        
        Text("Settings content would appear below...")
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 600)
}

#Preview("No Update") {
    VStack(spacing: 16) {
        UpdateBannerView().listening()
        
        Text("No banner should appear")
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 600)
}

#Preview("Banner in Settings Context") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            let view = UpdateBannerView()
            view
                .onAppear {
                    NotificationCenter.default.post(
                        name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
                        object: nil,
                        userInfo: [
                            "isUpdateAvailable": true,
                            "latestVersion": "2.0.0",
                            "releaseURL": "https://github.com/mrdemonwolf/wolfwave/releases"
                        ]
                    )
                }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("General Settings")
                    .sectionHeader()
                
                Text("This is where your settings would appear.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
        .padding()
    }
    .frame(width: 600, height: 400)
}


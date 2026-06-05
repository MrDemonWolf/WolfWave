//
//  UpdateBannerView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
    @State private var releaseURLString: String?
    @State private var isDismissed = false

    var body: some View {
        if isUpdateAvailable && !isDismissed {
            HStack(spacing: DSSpace.s3) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: DSFont.Size.lg))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: latestVersion)

                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Update Available")
                        .font(.system(size: DSFont.Size.body, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("WolfWave v\(latestVersion) is ready to download.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                if let releaseURLString {
                    Button("Download") {
                        ExternalLink.open(releaseURLString)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .controlSize(.small)
                    .accessibilityHint("Downloads the latest version of WolfWave")
                }

                Button {
                    withAnimation(.easeOut(duration: DSMotion.Duration.base)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: DSFont.Size.xs, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update banner")
            }
            .padding(.horizontal, DSSpace.s5)
            .padding(.vertical, DSSpace.s3)
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
                    for: Notification.Name.updateStateChanged
                )
            ) { notification in
                guard let update = notification.updateState else { return }
                let available = update.isUpdateAvailable

                if available {
                    latestVersion = update.latestVersion
                    releaseURLString = update.releaseURL ?? AppConstants.URLs.githubReleases
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
    VStack(spacing: DSSpace.s6) {
        let view = UpdateBannerView().listening()
        view
            .onAppear {
                NotificationCenter.default.postUpdateState(
                    isUpdateAvailable: true,
                    latestVersion: "1.2.0",
                    releaseURL: "https://github.com/mrdemonwolf/wolfwave/releases/tag/v1.2.0"
                )
            }
        
        Text("Settings content would appear below...")
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 600)
}

#Preview("No Update") {
    VStack(spacing: DSSpace.s6) {
        UpdateBannerView().listening()
        
        Text("No banner should appear")
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 600)
}

#Preview("Banner in Settings Context") {
    ScrollView {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            let view = UpdateBannerView().listening()
            view
                .onAppear {
                    NotificationCenter.default.postUpdateState(
                        isUpdateAvailable: true,
                        latestVersion: "2.0.0",
                        releaseURL: "https://github.com/mrdemonwolf/wolfwave/releases"
                    )
                }
            
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("General Settings")
                    .sectionHeader()
                
                Text("This is where your settings would appear.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        }
        .padding()
    }
    .frame(width: 600, height: 400)
}


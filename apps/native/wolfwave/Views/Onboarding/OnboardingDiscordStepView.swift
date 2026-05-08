//
//  OnboardingDiscordStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// Discord Rich Presence step. Brand tile + smart toggle card that brightens
/// with brand-tinted glow when enabled.
struct OnboardingDiscordStepView: View {

    // MARK: - Properties

    @Binding var presenceEnabled: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            BrandTile(
                background: AnyShapeStyle(AppConstants.Brand.discord),
                glowColor: AppConstants.Brand.discord,
                glyph:
                    Image("DiscordLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.white)
            )

            VStack(spacing: 6) {
                Text("Light up your Discord status")
                    .font(.system(size: 20, weight: .bold))

                Text("Friends will see what you're listening to — track, artist, and album art — right under your name.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ToggleSettingRow(
                title: "Show music on Discord",
                subtitle: "Updates every time the track changes.",
                isOn: $presenceEnabled,
                controlSize: .regular,
                accessibilityLabel: "Enable Discord Status",
                accessibilityIdentifier: "onboardingDiscordToggle",
                onChange: { newValue in
                    NotificationCenter.default.post(
                        name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
                        object: nil,
                        userInfo: ["enabled": newValue]
                    )
                }
            )
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(presenceEnabled
                          ? AppConstants.Brand.discord.opacity(0.10)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        presenceEnabled
                            ? AppConstants.Brand.discord.opacity(0.40)
                            : Color.primary.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: presenceEnabled ? AppConstants.Brand.discord.opacity(0.18) : .clear,
                radius: 18, x: 0, y: 6
            )
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.20), value: presenceEnabled)

            Text("Make sure Discord is open. We talk to it locally — nothing leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingDiscordStepView(presenceEnabled: .constant(false))
        .frame(width: 600, height: 380)
}

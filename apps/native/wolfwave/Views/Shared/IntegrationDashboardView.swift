//
//  IntegrationDashboardView.swift
//  wolfwave
//

import SwiftUI

/// Compact dashboard listing every place WolfWave is broadcasting right now.
/// Each row: brand glyph · plain-language status · chip · "Configure ›".
///
/// Used on the General tab (Screen B in the redesign). Sourced from live
/// integration state pushed via NotificationCenter.
struct IntegrationDashboardView: View {

    // MARK: - Inputs

    var twitchConnected: Bool
    var twitchChannel: String?
    var twitchViewerCount: Int?
    var discordConnected: Bool
    var widgetRunning: Bool
    var widgetURL: String?
    var remoteSendingEnabled: Bool
    var permissionPaused: Bool = false

    /// Routes to a specific Settings section when "Configure ›" is tapped.
    var configure: (Section) -> Void = { _ in }

    enum Section { case twitch, discord, obs, advanced }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Integrations")
                    .sectionSubHeader()
                Spacer()
                Text("Where WolfWave is broadcasting right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                row(
                    icon: brandIcon("TwitchLogo", fallback: "bubble.left.fill", color: Color(red: 0.57, green: 0.27, blue: 1.0)),
                    name: "Twitch chat",
                    chip: twitchChip,
                    subtitle: twitchSubtitle,
                    action: { configure(.twitch) }
                )
                Divider().padding(.leading, 44)
                row(
                    icon: brandIcon("DiscordLogo", fallback: "headphones", color: Color(red: 0.35, green: 0.40, blue: 0.95)),
                    name: "Discord profile",
                    chip: discordChip,
                    subtitle: discordSubtitle,
                    action: { configure(.discord) }
                )
                Divider().padding(.leading, 44)
                row(
                    icon: brandIcon("OBSLogo", fallback: "tv", color: .primary, isTemplate: true),
                    name: "Stream overlay",
                    chip: widgetChip,
                    subtitle: widgetSubtitle,
                    action: { configure(.obs) }
                )
                Divider().padding(.leading, 44)
                row(
                    icon: AnyView(
                        Image(systemName: "wifi")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                    ),
                    name: "Send to a remote site (optional)",
                    chip: remoteSendingEnabled
                        ? StatusChip(text: "On", color: .green)
                        : StatusChip(text: "Off", color: .secondary),
                    subtitle: remoteSendingEnabled
                        ? "Forwarding now-playing to your remote endpoint."
                        : "Only turn this on if your overlay lives somewhere else.",
                    action: { configure(.advanced) }
                )
            }
            .cardStyleUnpadded()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(
        icon: AnyView,
        name: String,
        chip: StatusChip,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            chip
            Button(action: action) {
                HStack(spacing: 2) {
                    Text("Configure")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Brand icon helper

    private func brandIcon(_ asset: String, fallback: String, color: Color, isTemplate: Bool = false) -> AnyView {
        AnyView(
            Group {
                if NSImage(named: asset) != nil {
                    Image(asset)
                        .renderingMode(isTemplate ? .template : .original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(isTemplate ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
                } else {
                    Image(systemName: fallback)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 22)
        )
    }

    // MARK: - Chips & subtitles

    private var twitchChip: StatusChip {
        if permissionPaused { return StatusChip(text: "Paused", color: .orange) }
        return twitchConnected
            ? StatusChip(text: "Live", color: .green)
            : StatusChip(text: "Off", color: .secondary)
    }

    private var twitchSubtitle: String {
        if permissionPaused { return "Will reply once Music permission is restored." }
        if twitchConnected {
            let channel = twitchChannel.map { "@\($0)" } ?? "your channel"
            if let n = twitchViewerCount, n > 0 {
                return "Connected to \(channel) · \(n) people watching"
            }
            return "Connected to \(channel)"
        }
        return "Sign in to bridge !song into chat."
    }

    private var discordChip: StatusChip {
        if permissionPaused { return StatusChip(text: "Paused", color: .orange) }
        return discordConnected
            ? StatusChip(text: "Showing now", color: .green)
            : StatusChip(text: "Off", color: .secondary)
    }

    private var discordSubtitle: String {
        if permissionPaused { return "Paused while Music permission is missing." }
        return discordConnected
            ? "Friends can see what you're playing."
            : "Turn it on to share Apple Music on your Discord profile."
    }

    private var widgetChip: StatusChip {
        if permissionPaused { return StatusChip(text: "Paused", color: .orange) }
        return widgetRunning
            ? StatusChip(text: "Ready for OBS", color: .green)
            : StatusChip(text: "Off", color: .secondary)
    }

    private var widgetSubtitle: String {
        if permissionPaused { return "Showing the last known track until permission is fixed." }
        if widgetRunning {
            return "Drop this URL into OBS: \(widgetURL ?? "http://localhost")"
        }
        return "Turn on the widget server to feed your overlay."
    }
}

#Preview {
    IntegrationDashboardView(
        twitchConnected: true,
        twitchChannel: "nightowlstream",
        twitchViewerCount: 12,
        discordConnected: true,
        widgetRunning: true,
        widgetURL: "http://localhost:8766",
        remoteSendingEnabled: false
    )
    .padding()
    .frame(width: 720)
    .background(WallpaperBloomBackground())
}

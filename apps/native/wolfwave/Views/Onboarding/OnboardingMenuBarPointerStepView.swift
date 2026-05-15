//
//  OnboardingMenuBarPointerStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/7/26.
//

import SwiftUI

/// Final orientation step — points the user up at the menu bar so they know where
/// WolfWave lives after the wizard closes. Animated arrow + sample menu-bar strip
/// with the TrayIcon highlighted.
struct OnboardingMenuBarPointerStepView: View {

    // MARK: - Animation State

    @State private var arrowBobbing = false
    @State private var iconPulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            menuBarPreview
                .padding(.bottom, 4)

            arrow

            VStack(spacing: 8) {
                Text("Find WolfWave up here")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Click the wolf in your menu bar any time to see what's playing or change settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                arrowBobbing = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                iconPulsing = true
            }
        }
        .onDisappear {
            // Stop the CADisplayLink-driven loops once the user moves past this step.
            withAnimation(.linear(duration: 0)) {
                arrowBobbing = false
                iconPulsing = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Find WolfWave in your menu bar.")
    }

    // MARK: - Menu Bar Preview

    private var menuBarPreview: some View {
        HStack(spacing: 8) {
            Spacer()

            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 14)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(iconPulsing ? 0.20 : 0.08))
                    .frame(width: 26, height: 22)

                if let trayIcon = NSImage(named: "TrayIcon") {
                    Image(nsImage: trayIcon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.primary)
                }
            }
            .shadow(
                color: Color.accentColor.opacity(iconPulsing ? 0.40 : 0),
                radius: 10, x: 0, y: 0
            )

            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 14)
            }

            Text(currentTime)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    // MARK: - Arrow

    private var arrow: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .offset(y: arrowBobbing ? -4 : 4)
            .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private var currentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: Date())
    }
}

// MARK: - Preview

#Preview {
    OnboardingMenuBarPointerStepView()
        .frame(width: 600, height: 380)
}

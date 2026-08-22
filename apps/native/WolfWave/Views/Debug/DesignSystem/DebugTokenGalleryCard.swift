//
//  DebugTokenGalleryCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// DEBUG-only gallery of every design token, rendered live.
///
/// Each section iterates the ordered lists that `design-system/scripts/generate.ts`
/// emits next to the named constants (`DSColor.groups`, `DSSpace.all`, …), so
/// the gallery cannot list a token that `tokens.json` no longer has, or miss one
/// it gained. Nothing here is hand-listed.
struct DebugTokenGalleryCard: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            Text("""
                Every token in Tokens.generated.swift, read from the generated lists \
                so nothing here can drift from tokens.json.
                """)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            colorsSection
            Divider()
            typographySection
            Divider()
            spacingSection
            Divider()
            radiusSection
            Divider()
            motionSection
            Divider()
            motionGallerySection
            Divider()
            dimensionsSection
        }
        .cardStyle()
    }

    // MARK: - Colors

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Colors", symbol: "DSColor.groups")
            ForEach(DSColor.groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    Text(group.name)
                        .captionText()
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Metrics.swatchColumn), spacing: DSSpace.s3)],
                        alignment: .leading,
                        spacing: DSSpace.s3
                    ) {
                        ForEach(group.tokens, id: \.name) { token in
                            swatch(token)
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ token: (name: String, hex: String, color: Color)) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s1) {
            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                .fill(token.color)
                .frame(height: Metrics.swatchHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            Text(token.name)
                .font(.system(size: DSFont.Size.xs, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(token.hex)
                .font(.system(size: DSFont.Size.xs, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.name), \(token.hex)")
    }

    // MARK: - Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Typography", symbol: "DSFont.Size.all · DSFont.Weight.all")
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                ForEach(DSFont.Size.all, id: \.name) { token in
                    HStack(alignment: .firstTextBaseline, spacing: DSSpace.s4) {
                        tokenLabel(token.name, points(token.value))
                        Text("The quick brown wolf")
                            .font(.system(size: token.value))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: DSSpace.s6) {
                ForEach(DSFont.Weight.all, id: \.name) { token in
                    VStack(alignment: .leading, spacing: DSSpace.s0) {
                        Text("Wolf")
                            .font(.system(size: DSFont.Size.lg, weight: token.value))
                        Text(token.name)
                            .font(.system(size: DSFont.Size.xs, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Spacing", symbol: "DSSpace.all")
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                ForEach(DSSpace.all, id: \.name) { token in
                    HStack(spacing: DSSpace.s4) {
                        tokenLabel(token.name, points(token.value))
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: token.value, height: DSSpace.s2)
                    }
                }
            }
        }
    }

    // MARK: - Radius

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Radius", symbol: "DSRadius.all")
            HStack(alignment: .top, spacing: DSSpace.s4) {
                ForEach(DSRadius.all, id: \.name) { token in
                    VStack(spacing: DSSpace.s1) {
                        // A radius past half the side (the 9999 "pill") clamps to a capsule.
                        RoundedRectangle(cornerRadius: token.value, style: .continuous)
                            .fill(Color.accentColor.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: token.value, style: .continuous)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                            .frame(width: Metrics.radiusSample, height: Metrics.radiusSample)
                        Text(token.name)
                            .font(.system(size: DSFont.Size.xs, design: .monospaced))
                        Text(token.value >= Metrics.radiusSample / 2 ? "capsule" : points(token.value))
                            .font(.system(size: DSFont.Size.xs))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Motion

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Motion", symbol: "DSMotion.Duration.all · DSMotion.Spring.all")
            Text("Press Play to run each token. Reduce Motion is \(reduceMotion ? "on, so nothing animates" : "off").")
                .captionText()
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                ForEach(DSMotion.Duration.all, id: \.name) { token in
                    MotionTrackRow(
                        name: token.name,
                        detail: "\(formatted(token.value))s",
                        animation: reduceMotion ? nil : .easeInOut(duration: token.value)
                    )
                }
            }
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                ForEach(DSMotion.Spring.all, id: \.name) { token in
                    MotionTrackRow(
                        name: token.name,
                        detail: "response \(formatted(token.response)) · damping \(formatted(token.damping))",
                        animation: reduceMotion ? nil : token.animation
                    )
                }
            }
        }
    }

    private var motionGallerySection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Motion gallery", symbol: "contentTransition · symbolEffect · TimelineView · AsyncImage")
            MotionGallerySection()
        }
    }

    // MARK: - Dimensions

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            family("Dimensions", symbol: "DSDimension.groups")
            ForEach(DSDimension.groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    Text(group.name)
                        .captionText()
                    Grid(alignment: .leading, horizontalSpacing: DSSpace.s6, verticalSpacing: DSSpace.s1) {
                        ForEach(group.tokens, id: \.name) { token in
                            GridRow {
                                Text(token.name)
                                    .font(.system(size: DSFont.Size.sm, design: .monospaced))
                                Text(points(token.value))
                                    .font(.system(size: DSFont.Size.sm))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func family(_ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.s2) {
            Text(title)
                .sectionEyebrow()
            Text(symbol)
                .font(.system(size: DSFont.Size.xs, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func tokenLabel(_ name: String, _ value: String) -> some View {
        HStack(spacing: DSSpace.s1) {
            Text(name)
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
            Text(value)
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.secondary)
        }
        .frame(width: Metrics.labelColumn, alignment: .leading)
    }

    private func points(_ value: CGFloat) -> String {
        "\(formatted(Double(value)))pt"
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Gallery-only layout sizes. Not design tokens: they size the samples, not the product.
    private enum Metrics {
        static let swatchColumn: CGFloat = 120
        static let swatchHeight: CGFloat = 44
        static let radiusSample: CGFloat = 56
        static let labelColumn: CGFloat = 104
    }
}

// MARK: - Motion track

/// One duration or spring token: a dot that slides across a fixed track with
/// the token's animation, so overshoot and timing are comparable side by side.
private struct MotionTrackRow: View {

    let name: String
    let detail: String
    /// `nil` when Reduce Motion is on; the dot then jumps.
    let animation: Animation?

    @State private var atEnd = false

    var body: some View {
        HStack(spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(name)
                    .font(.system(size: DSFont.Size.sm, design: .monospaced))
                Text(detail)
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Metrics.labelColumn, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: DSSpace.s0)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: Metrics.dot, height: Metrics.dot)
                    .offset(x: atEnd ? Metrics.track - Metrics.dot : 0)
            }
            .frame(width: Metrics.track)

            Button("Play") {
                withAnimation(animation) { atEnd.toggle() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
            .accessibilityLabel("Play \(name)")
        }
    }

    private enum Metrics {
        static let labelColumn: CGFloat = 200
        static let track: CGFloat = 200
        static let dot: CGFloat = 14
    }
}

#Preview {
    DebugTokenGalleryCard()
        .padding()
        .frame(width: 600)
}
#endif

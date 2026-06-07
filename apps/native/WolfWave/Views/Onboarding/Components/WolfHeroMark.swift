//
//  WolfHeroMark.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

// MARK: - WolfHeroMark

/// Reusable wolf silhouette + howl-wave bars hero mark.
///
/// Path data is ported from the widget overlay SVG (`Resources/widget.html`)
/// so the onboarding hero, completion hero, and future surfaces (MonthlyWrap)
/// share the same visual language as the tray icon and overlay widget.
///
/// - The wolf head is a single `Path` filled with even-odd rule so the eye
///   sockets carve out of the silhouette.
/// - The eight howl-wave bars are individual `RoundedRectangle`s so each can
///   animate its opacity independently when `animatedBars == true`.
struct WolfHeroMark: View {

    // MARK: - Style

    /// Fill treatment for the silhouette + bars.
    enum Style: Equatable {
        /// Flat tint applied to silhouette and bars. Pass `.primary` for the
        /// theme-adaptive black/white treatment that matches the menu-bar
        /// template icon — use this for small or inline marks.
        case mono(Color)
        /// WolfWave brand gradient (navy → royal blue) masked over the
        /// silhouette + bars. The stops adapt to the color scheme so the mark
        /// stays vivid in both Light and Dark (the navy light-stop would
        /// otherwise sink into a black background). Reserve for hero surfaces.
        case brandGradient
    }

    // MARK: - Properties

    /// Square render size in points.
    var size: CGFloat
    var style: Style = .mono(.primary)
    /// When `true` the howl-wave bars run a staggered opacity entrance.
    /// Honors `reduceMotion`.
    var animatedBars: Bool = false
    /// Caller-provided `accessibilityReduceMotion` value. Caller is responsible
    /// for forwarding the environment value when `animatedBars` is enabled.
    var reduceMotion: Bool = false

    // MARK: - Animation State

    @State private var barsAtFinalOpacity: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        Group {
            switch style {
            case .mono(let color):
                silhouette(tint: color)
            case .brandGradient:
                brandGradient
                    .mask(silhouette(tint: .white))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("WolfWave wolf mark")
        .task(id: animatedBars) {
            if !animatedBars || reduceMotion {
                barsAtFinalOpacity = true
                return
            }
            barsAtFinalOpacity = false
            // Brief delay so the entrance reads as a separate beat from the
            // host view's own fade-in.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                barsAtFinalOpacity = true
            }
        }
    }

    // MARK: - Silhouette Composition

    @ViewBuilder
    private func silhouette(tint: Color) -> some View {
        ZStack {
            WolfHeadShape()
                .fill(tint, style: FillStyle(eoFill: true, antialiased: true))
            HowlBars(
                tint: tint,
                staggered: animatedBars && !reduceMotion,
                progress: barsAtFinalOpacity ? 1 : 0
            )
        }
    }

    /// WolfWave's own brand gradient, theme-adaptive.
    ///
    /// - Light: navy → royal blue (the canonical brand stops). High contrast
    ///   on a white background.
    /// - Dark: royal blue → sky blue. The navy light-stop is near-black
    ///   (`#0A2540`) and would vanish on a dark background, so the dark variant
    ///   shifts up the brand ramp to stay vivid.
    private var brandGradient: LinearGradient {
        let stops: [Color] = colorScheme == .dark
            ? [AppConstants.Brand.wolfwaveGradientEnd, DSColor.brand300]
            : [AppConstants.Brand.wolfwaveGradientStart, AppConstants.Brand.wolfwaveGradientEnd]
        return LinearGradient(
            colors: stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - WolfHeadShape

/// Wolf head silhouette (ears + skull + eye sockets). Fill with even-odd
/// rule so the eye sockets cut through. ViewBox: `8 2 84 94` from widget SVG.
private struct WolfHeadShape: Shape {

    func path(in rect: CGRect) -> Path {
        let box = WolfViewBox(rect: rect)
        var path = Path()

        // Skull / head body. Closed outline matching widget.html.
        path.move(to: box.point(50, 18))
        path.addCurve(
            to: box.point(72, 42),
            control1: box.point(61, 16),
            control2: box.point(72, 26)
        )
        path.addLine(to: box.point(70, 57))
        path.addLine(to: box.point(62, 67))
        path.addLine(to: box.point(50, 71))
        path.addLine(to: box.point(38, 67))
        path.addLine(to: box.point(30, 57))
        path.addLine(to: box.point(28, 42))
        path.addCurve(
            to: box.point(50, 18),
            control1: box.point(28, 26),
            control2: box.point(39, 16)
        )
        path.closeSubpath()

        // Left ear triangle
        path.move(to: box.point(32, 38))
        path.addLine(to: box.point(35.5, 9))
        path.addLine(to: box.point(46, 33))
        path.closeSubpath()

        // Right ear triangle
        path.move(to: box.point(68, 38))
        path.addLine(to: box.point(64.5, 9))
        path.addLine(to: box.point(54, 33))
        path.closeSubpath()

        // Left eye socket, carved via even-odd.
        path.move(to: box.point(32, 43))
        path.addCurve(
            to: box.point(46.5, 43),
            control1: box.point(34, 37.5),
            control2: box.point(44.5, 37.5)
        )
        path.addCurve(
            to: box.point(32, 43),
            control1: box.point(44.5, 48.5),
            control2: box.point(34, 48.5)
        )
        path.closeSubpath()

        // Right eye socket, carved via even-odd.
        path.move(to: box.point(53.5, 43))
        path.addCurve(
            to: box.point(68, 43),
            control1: box.point(55.5, 37.5),
            control2: box.point(66, 37.5)
        )
        path.addCurve(
            to: box.point(53.5, 43),
            control1: box.point(66, 48.5),
            control2: box.point(55.5, 48.5)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - HowlBars

/// Eight howl-wave bars (four per side) with staggered entrance opacity.
private struct HowlBars: View {

    let tint: Color
    let staggered: Bool
    /// `0` = bars hidden, `1` = bars at final opacity. Driven by parent.
    let progress: Double

    private struct Bar {
        let originX: CGFloat
        let originY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let finalOpacity: Double
        let stagger: Double
    }

    /// Bars defined in viewBox coords from widget.html.
    /// Inner bars hit full opacity; outer bars fall off (0.78 / 0.55 / 0.33).
    private static let bars: [Bar] = [
        Bar(originX: 25.0, originY: 38, width: 4.5, height: 35, finalOpacity: 1.00, stagger: 0.00),
        Bar(originX: 18.5, originY: 47, width: 4.5, height: 26, finalOpacity: 0.78, stagger: 0.25),
        Bar(originX: 12.0, originY: 55, width: 4.5, height: 18, finalOpacity: 0.55, stagger: 0.50),
        Bar(originX: 5.5, originY: 62, width: 4.5, height: 11, finalOpacity: 0.33, stagger: 0.75),
        Bar(originX: 70.5, originY: 38, width: 4.5, height: 35, finalOpacity: 1.00, stagger: 0.00),
        Bar(originX: 77.0, originY: 47, width: 4.5, height: 26, finalOpacity: 0.78, stagger: 0.25),
        Bar(originX: 83.5, originY: 55, width: 4.5, height: 18, finalOpacity: 0.55, stagger: 0.50),
        Bar(originX: 90.0, originY: 62, width: 4.5, height: 11, finalOpacity: 0.33, stagger: 0.75)
    ]

    var body: some View {
        GeometryReader { geo in
            let box = WolfViewBox(rect: CGRect(origin: .zero, size: geo.size))
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                let origin = box.point(bar.originX, bar.originY)
                let renderedWidth = box.scale(bar.width)
                let renderedHeight = box.scale(bar.height)
                RoundedRectangle(cornerRadius: box.scale(2.25), style: .continuous)
                    .fill(tint)
                    .frame(width: renderedWidth, height: renderedHeight)
                    .position(
                        x: origin.x + renderedWidth / 2,
                        y: origin.y + renderedHeight / 2
                    )
                    .opacity(opacity(for: bar))
            }
        }
    }

    private func opacity(for bar: Bar) -> Double {
        guard staggered else { return bar.finalOpacity }
        // Inner bars (stagger 0) fade in first, outer bars (stagger 0.75)
        // trail. Each bar's window is the remaining 0.25 of the timeline.
        let local = max(0, min(1, (progress - bar.stagger) / 0.25))
        return bar.finalOpacity * local
    }
}

// MARK: - WolfViewBox

/// Maps the widget SVG viewBox (`8 2 84 94`) into a target `CGRect`,
/// preserving aspect ratio (centered).
nonisolated private struct WolfViewBox {

    static let originX: CGFloat = 8
    static let originY: CGFloat = 2
    static let widthVB: CGFloat = 84
    static let heightVB: CGFloat = 94

    let unit: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    init(rect: CGRect) {
        let scaleX = rect.width / Self.widthVB
        let scaleY = rect.height / Self.heightVB
        let unit = min(scaleX, scaleY)
        self.unit = unit
        self.offsetX = rect.minX + (rect.width - Self.widthVB * unit) / 2
        self.offsetY = rect.minY + (rect.height - Self.heightVB * unit) / 2
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: offsetX + (x - Self.originX) * unit,
            y: offsetY + (y - Self.originY) * unit
        )
    }

    func scale(_ length: CGFloat) -> CGFloat {
        length * unit
    }
}

// MARK: - Previews

#Preview("mono: primary") {
    WolfHeroMark(size: 120, style: .mono(.primary))
        .padding(DSSpace.s7)
}

#Preview("brand gradient: animated") {
    WolfHeroMark(size: 120, style: .brandGradient, animatedBars: true)
        .padding(DSSpace.s7)
}

#Preview("brand gradient: dark") {
    WolfHeroMark(size: 120, style: .brandGradient, animatedBars: true)
        .padding(DSSpace.s7)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
}

#Preview("mono: twitch tint, small") {
    WolfHeroMark(size: 44, style: .mono(AppConstants.Brand.twitch))
        .padding(DSSpace.s4)
}

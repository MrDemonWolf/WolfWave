//
//  TwitchGlitchShape.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/7/26.
//

import SwiftUI

/// A SwiftUI `Shape` that draws the Twitch "Glitch" logo silhouette.
///
/// The shape consists of the outer speech-bubble polygon and two rectangular
/// "eye" cutouts. Use `FillStyle(eoFill: true)` so the cutouts punch through
/// correctly with the even-odd rule.
///
/// Usage:
/// ```swift
/// TwitchGlitchShape()
///     .fill(style: FillStyle(eoFill: true))
///     .frame(width: 16, height: 16)
/// ```
struct TwitchGlitchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        // All coordinates normalized to a 24x28 reference grid,
        // matching the official Twitch Glitch proportions.
        let refW: CGFloat = 24
        let refH: CGFloat = 28

        func x(_ v: CGFloat) -> CGFloat { v / refW * w }
        func y(_ v: CGFloat) -> CGFloat { v / refH * h }

        var path = Path()

        // -- Outer silhouette (speech-bubble polygon) --
        path.move(to: CGPoint(x: x(2), y: y(0)))       // top-left notch start
        path.addLine(to: CGPoint(x: x(0), y: y(3)))     // left indent
        path.addLine(to: CGPoint(x: x(0), y: y(23)))    // left side down
        path.addLine(to: CGPoint(x: x(5), y: y(28)))    // bottom-left tab
        path.addLine(to: CGPoint(x: x(9), y: y(28)))    // bottom tab right edge
        path.addLine(to: CGPoint(x: x(12), y: y(25)))   // inner notch
        path.addLine(to: CGPoint(x: x(16), y: y(25)))   // bottom shelf
        path.addLine(to: CGPoint(x: x(21), y: y(20)))   // right leg bottom
        path.addLine(to: CGPoint(x: x(21), y: y(15)))   // right indent bottom
        path.addLine(to: CGPoint(x: x(24), y: y(12)))   // right indent tip
        path.addLine(to: CGPoint(x: x(24), y: y(0)))    // top-right corner
        path.closeSubpath()

        // -- Left eye cutout --
        path.addRect(CGRect(
            x: x(8), y: y(8),
            width: x(3), height: y(7)
        ))

        // -- Right eye cutout --
        path.addRect(CGRect(
            x: x(14), y: y(8),
            width: x(3), height: y(7)
        ))

        return path
    }
}

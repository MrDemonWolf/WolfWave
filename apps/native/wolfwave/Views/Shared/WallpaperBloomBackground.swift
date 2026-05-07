//
//  WallpaperBloomBackground.swift
//  wolfwave
//

import SwiftUI

/// Soft wallpaper bloom rendered behind glass surfaces in the Settings detail
/// pane. Three radial gradients (top-left blue, right pink, bottom mint) at
/// low opacity give the Liquid Glass cards something to refract.
///
/// Usage: place at the very back of a ZStack — `.background(WallpaperBloomBackground())`.
struct WallpaperBloomBackground: View {

    var body: some View {
        Canvas { context, size in
            // Three soft color blooms. Canvas keeps it cheap (one drawcall, no nested Views).
            drawBloom(
                in: context, size: size,
                center: CGPoint(x: size.width * 0.12, y: 0),
                radius: 480,
                color: Color(red: 0.47, green: 0.67, blue: 1.0).opacity(0.30)
            )
            drawBloom(
                in: context, size: size,
                center: CGPoint(x: size.width * 1.0, y: size.height * 0.30),
                radius: 460,
                color: Color(red: 1.0, green: 0.55, blue: 0.78).opacity(0.22)
            )
            drawBloom(
                in: context, size: size,
                center: CGPoint(x: size.width * 0.5, y: size.height * 1.10),
                radius: 460,
                color: Color(red: 0.47, green: 1.0, blue: 0.82).opacity(0.20)
            )
        }
        .blur(radius: 30)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func drawBloom(
        in context: GraphicsContext,
        size: CGSize,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let gradient = Gradient(colors: [color, color.opacity(0)])
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                gradient,
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }
}

#Preview {
    ZStack {
        WallpaperBloomBackground()
        Text("Glass content here")
            .padding(40)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
    .frame(width: 900, height: 640)
}

//
//  WolfHeroMark.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

// MARK: - WolfHeroMark

/// Scalable presentation wrapper around the canonical `WolfMark` template asset.
struct WolfHeroMark: View {

    // MARK: - Style

    enum Style: Equatable {
        /// Flat tint for small or inline marks.
        case mono(Color)
        /// Theme-adaptive WolfWave gradient for hero surfaces.
        case brandGradient
    }

    // MARK: - Properties

    /// Square render size in points.
    var size: CGFloat
    var style: Style = .mono(.primary)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        Group {
            switch style {
            case .mono(let color):
                mark.foregroundStyle(color)
            case .brandGradient:
                brandGradient.mask(mark)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("WolfWave wolf mark")
    }

    // MARK: - Private Views

    private var mark: some View {
        Image("WolfMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
    }

    private var brandGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [AppConstants.Brand.wolfwaveGradientEnd, DSColor.brand300]
            : [AppConstants.Brand.wolfwaveGradientStart, AppConstants.Brand.wolfwaveGradientEnd]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Previews

#Preview("mono: primary") {
    WolfHeroMark(size: 120, style: .mono(.primary))
        .padding(DSSpace.s7)
}

#Preview("brand gradient") {
    WolfHeroMark(size: 120, style: .brandGradient)
        .padding(DSSpace.s7)
}

#Preview("brand gradient: dark") {
    WolfHeroMark(size: 120, style: .brandGradient)
        .padding(DSSpace.s7)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
}

#Preview("mono: twitch tint, small") {
    WolfHeroMark(size: 44, style: .mono(AppConstants.Brand.twitch))
        .padding(DSSpace.s4)
}

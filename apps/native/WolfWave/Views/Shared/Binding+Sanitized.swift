//
//  Binding+Sanitized.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

// MARK: - Sanitized Bindings

/// Guards for `@AppStorage`-backed controls whose persisted value may be
/// outside the range or tag set the control accepts.
///
/// A `Picker` handed a selection with no matching tag, or a `Slider` handed a
/// value outside its bounds, is not merely wrong on screen. SwiftUI's segmented
/// picker traps on it, which takes down the settings window. The value only has
/// to be *stored*, not chosen: a hand-edited plist, `defaults write`, an older
/// build, or a test process sharing the app's domain will all do it.
///
/// These wrap the projected value rather than replacing the property, so the
/// `@AppStorage` property remains the view's SwiftUI dependency and still
/// invalidates the view when the underlying defaults change. Sanitizing in the
/// getter also means the first render is safe, which an `onAppear` repair would
/// not be: `body` runs, and traps, before `onAppear` ever fires.
///
/// The setter passes through unchanged. A control can only ever produce a valid
/// value, and healing the stored value as a side effect of drawing would fight
/// whatever wrote it.
extension Binding where Value == Int {

    /// Renders as `fallback` when the stored value is not one of `allowed`.
    func snapped(to allowed: [Int], fallback: Int) -> Binding<Int> {
        Binding(
            get: { Preferences.resolveAllowed(wrappedValue, allowed: Set(allowed), default: fallback) },
            set: { wrappedValue = $0 }
        )
    }
}

extension Binding where Value == Double {

    /// Clamps into `range`; a non-finite stored value renders as `fallback`.
    func clamped(to range: ClosedRange<Double>, fallback: Double) -> Binding<Double> {
        Binding(
            get: { Preferences.resolveClamped(wrappedValue, range: range, default: fallback) },
            set: { wrappedValue = $0 }
        )
    }
}

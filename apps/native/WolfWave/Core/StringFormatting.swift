//
//  StringFormatting.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Small, shared `String` shaping helpers for chat replies and UI labels.
///
/// Centralizes the truncation idioms that were duplicated across the Twitch
/// command replies (`!sr` not-found messages, bit-cheer fallbacks) so the
/// length cap and ellipsis live in one place instead of repeated inline
/// `count > 30 ? prefix(30) + "..."` expressions.
nonisolated enum StringFormatting {

    /// Truncates `text` to `maxLength` characters, appending an ellipsis when it
    /// was shortened. Returns the original string when it already fits.
    ///
    /// Used for echoing a viewer's search query back into chat without letting a
    /// pasted wall of text blow past Twitch's message limit.
    static func truncatedWithEllipsis(_ text: String, maxLength: Int = 30) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}

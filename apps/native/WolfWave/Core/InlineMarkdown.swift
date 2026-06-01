//
//  InlineMarkdown.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Parses a runtime `String` as inline Markdown into an `AttributedString`.
///
/// `Text("**bold**")` renders Markdown only for string *literals*. A runtime
/// `String` handed to `Text` is shown verbatim, so a callout built from stored
/// copy (e.g. `CalloutBanner` / `HintRow` messages) would display literal
/// asterisks. This helper runs the string through `AttributedString`'s inline
/// Markdown parser, preserving whitespace and falling back to the plain string
/// if parsing fails.
enum InlineMarkdown {

    /// Returns `string` parsed as inline Markdown, or the verbatim string on failure.
    static func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}

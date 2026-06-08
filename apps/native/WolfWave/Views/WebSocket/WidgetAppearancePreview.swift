//
//  WidgetAppearancePreview.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import WebKit

/// Live, in-app preview of the now-playing overlay widget.
///
/// This is the **real** overlay, not a SwiftUI re-creation of it. It loads the
/// bundled `widget.html` (the exact file OBS renders) in a `WKWebView` running
/// in preview mode, so the preview is pixel-identical to what goes live. Every
/// theme gradient, backdrop blur, noise layer, and glow renders through the same
/// code path. A previous version hand-rolled the card in SwiftUI and drifted out
/// of sync with the web renderer on every theme change; this can't.
///
/// Preview mode (see `setupPreview` in `apps/widget/src/widget.ts`) swaps the
/// WebSocket feed for a direct bridge: we inject an invented demo track once,
/// then push the live appearance *draft* on every edit via `window.WWPreview`.
/// Nothing reaches the real overlay until the user taps Apply. The page paints a
/// checkerboard behind the card so the transparent Default theme reads correctly.
struct WidgetAppearancePreview: View {
    /// The appearance values to render. The settings card passes its live
    /// *draft* here, so the preview tracks every edit instantly even though
    /// those edits don't reach the real overlay until the user taps Apply.
    let config: WidgetAppearanceConfig

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            header
            stage
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: "eye.fill")
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                Text("Live Preview").sectionEyebrow()
            }
            Text("Exactly how your overlay looks. Tap Apply to push changes live.")
                .fieldSubtitle()
        }
    }

    // MARK: - Stage

    private var stage: some View {
        WidgetPreviewWebView(config: config)
            .frame(height: stageHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Widget preview, \(config.theme) theme, \(config.layout) layout")
    }

    /// Fixed to the tallest layout (Vertical) so switching layouts never resizes
    /// the stage. A growing/shrinking preview shifts everything below it and
    /// makes the settings pane scroll-jump, so the height stays constant and the
    /// web-rendered card sizes itself within it (the page caps each layout's
    /// width, exactly as OBS does).
    private var stageHeight: CGFloat {
        (DSWidgetLayouts.sizes.values.map(\.height).max() ?? 280) + DSSpace.s11
    }
}

// MARK: - Web Preview Host

/// Hosts the bundled `widget.html` in a `WKWebView` and drives it through the
/// `window.WWPreview` bridge. The view is created once; appearance edits arrive
/// via `updateNSView` and are pushed to the already-loaded page with a tiny
/// `evaluateJavaScript` call, so changing theme/layout/font is instant.
private struct WidgetPreviewWebView: NSViewRepresentable {
    let config: WidgetAppearanceConfig

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        // Flip the bundle into preview mode *before* its scripts run, so boot
        // takes the preview path (no WebSocket) instead of trying to connect.
        controller.addUserScript(
            WKUserScript(
                source: "window.__WW_PREVIEW__ = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // The page paints its own checkerboard stage; keep the web view opaque
        // and let that show through (no private-API transparency needed).
        webView.allowsMagnification = false
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.pendingConfig = config

        if let url = Bundle.main.url(forResource: "widget", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            Log.error("WidgetAppearancePreview: widget.html not found in bundle", category: "WebSocket")
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingConfig = config
        if context.coordinator.isLoaded {
            context.coordinator.applyConfig(config, to: webView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var pendingConfig: WidgetAppearanceConfig?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            injectDemoTrack(into: webView)
            if let config = pendingConfig {
                applyConfig(config, to: webView)
            }
        }

        /// Seed the card with an invented demo track (wolf song + wolf-species
        /// "artist", no artwork URL so the page draws its WolfWave wolf-mark
        /// fallback). Never real artists, songs, or third-party album art.
        private func injectDemoTrack(into webView: WKWebView) {
            let js = """
            if (window.WWPreview) {
              window.WWPreview.track({
                track: "Midnight Howl",
                artist: "Timber Wolf",
                album: "Howls & Echoes",
                duration: 192,
                elapsed: 78,
                isPlaying: true
              });
            }
            """
            webView.evaluateJavaScript(js)
        }

        /// Push the draft appearance to the page. The config is serialized via
        /// `JSONSerialization`, so a font family containing quotes can't break
        /// out of the injected JS string.
        func applyConfig(_ config: WidgetAppearanceConfig, to webView: WKWebView) {
            guard let json = config.previewJSON else { return }
            webView.evaluateJavaScript("if (window.WWPreview) { window.WWPreview.config(\(json)); }")
        }
    }
}

// MARK: - Appearance Config

/// The five user-tunable widget appearance values as one `Equatable` value.
///
/// The settings card edits a *draft* copy of this so changes only reach the live
/// overlay (and `UserDefaults`, which `WebSocketServerService.broadcastWidgetConfig()`
/// reads) when the user taps Apply. The preview renders whatever draft it's handed.
struct WidgetAppearanceConfig: Equatable {
    var theme: String
    var layout: String
    var textColor: String
    var backgroundColor: String
    var fontFamily: String

    /// Snapshot the currently-applied values from `UserDefaults`.
    static func loadApplied(_ defaults: UserDefaults = .standard) -> WidgetAppearanceConfig {
        WidgetAppearanceConfig(
            theme: defaults.string(forKey: AppConstants.UserDefaults.widgetTheme) ?? "Default",
            layout: defaults.string(forKey: AppConstants.UserDefaults.widgetLayout) ?? "Horizontal",
            textColor: defaults.string(forKey: AppConstants.UserDefaults.widgetTextColor) ?? "#FFFFFF",
            backgroundColor: defaults.string(forKey: AppConstants.UserDefaults.widgetBackgroundColor) ?? "#1A1A2E",
            fontFamily: defaults.string(forKey: AppConstants.UserDefaults.widgetFontFamily) ?? "System Default"
        )
    }

    /// Whether the chosen theme exposes editable text/background colors. Preset
    /// themes (Dark, Light, Neon) ship fixed palettes. `nonisolated` so the pure
    /// lookup is usable off the main actor (and from test autoclosures).
    nonisolated var themeCustomizable: Bool {
        DSWidgetThemes.resolve(theme).userCustomizable
    }

    /// The five fields as a `widget_config`-shaped JSON object string, ready to
    /// splice into a `window.WWPreview.config(...)` call. Built with
    /// `JSONSerialization` so user-chosen values (e.g. a font name with a quote)
    /// are escaped and can't break out of the injected JS. `nonisolated` so the
    /// pure serialization is usable off the main actor (and from test autoclosures).
    nonisolated var previewJSON: String? {
        let payload: [String: String] = [
            "theme": theme,
            "layout": layout,
            "textColor": textColor,
            "backgroundColor": backgroundColor,
            "fontFamily": fontFamily,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

// MARK: - Preview

#Preview("Widget Appearance Preview") {
    ScrollView {
        WidgetAppearancePreview(config: .loadApplied())
            .padding()
            .frame(width: 560)
    }
}

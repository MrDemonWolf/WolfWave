/* ═══════════════════════════════════════════════════════════════════════════
 *  WolfWave OBS Widget — Runtime
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  Goal of this file:
 *  -----------------
 *  Render a now-playing card driven by a WebSocket feed from the native
 *  WolfWave app (`WebSocketServerService.swift`). The card lives inside an
 *  OBS Browser Source, so it must:
 *
 *    • Boot fast and never appear blank (we show a placeholder while
 *      waiting for the first frame).
 *    • Be resilient to disconnects (auto-reconnect with exponential backoff).
 *    • Never re-trigger the bouncy entrance on every track skip — instead
 *      crossfade the inner content only.
 *    • Smoothly drain progress to zero when playback stops.
 *
 *  How the server talks to us:
 *  ---------------------------
 *  Five message types arrive on the WS feed (schemas frozen by the Swift
 *  tests `WebSocketServerServiceTests`/`WidgetHTTPServiceTests`):
 *
 *    • now_playing     { track, artist, album, duration, elapsed, isPlaying, artworkURL }
 *    • progress        { elapsed, duration, isPlaying }                  // ~1Hz
 *    • playback_state  { isPlaying, track, artist, album }
 *    • widget_config   { theme, layout, textColor, backgroundColor, fontFamily }
 *    • welcome         {}                                                // handshake ack
 *
 *  We do NOT push back. This is a one-way feed.
 *
 *  Visual state machine:
 *  ---------------------
 *
 *      ┌────────────┐     play       ┌──────────────┐     RAF tick     ┌─────────────┐
 *      │ hidden     │ ─────────────▶ │ entering     │ ───────────────▶ │ visible     │
 *      └────────────┘                └──────────────┘                  └─────────────┘
 *             ▲                                                                │
 *             │                                                                │ stop / quit
 *             │                                                                ▼
 *             │            ┌──────────────┐    500ms timer      ┌──────────────┐
 *             └────────────┤ hidden       │ ◀──────────────────┤ exiting       │
 *                          └──────────────┘                    └───────────────┘
 *
 *  Track-change happens on the inner DOM only (.track-meta / .artwork swap
 *  classes), never re-triggering the container animation. This is what makes
 *  rapid skips feel calm on stream.
 *
 *  Section map (use Cmd-F):
 *    ╔ CONFIG / FALLBACKS ╗
 *    ╔ STATE              ╗
 *    ╔ TYPES              ╗
 *    ╔ HELPERS            ╗
 *    ╔ THEME + LAYOUT     ╗
 *    ╔ PROGRESS LOOP      ╗
 *    ╔ TRANSITIONS        ╗
 *    ╔ RENDER             ╗
 *    ╔ WEBSOCKET          ╗
 *    ╔ MESSAGE HANDLERS   ╗
 *    ╔ BOOT               ╗
 * ═══════════════════════════════════════════════════════════════════════════ */

declare global {
  interface Window {
    WW_TOKENS?: WWTokens;
  }
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  CONFIG / FALLBACKS                                                    ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  URL-derived config + the design-system fallback shim. The shim only kicks
 *  in if `widget-tokens.generated.js` failed to load (file:// or stale build),
 *  so the widget never throws — it falls back to the Default theme/layout.
 */

const params = new URLSearchParams(location.search);
const wsPort = params.get("port") || params.get("wsPort") || "8765";
const autohide = Number(params.get("duration") || "0");
const hideAlbumArt = params.has("hideAlbumArt");

// Auth token. `WidgetHTTPService` substitutes the live token for the
// `__WOLFWAVE_TOKEN__` sentinel when it serves this file over loopback. When
// the page is opened directly (file://) we fall back to the `?token=` query.
//
// Why a subprotocol header instead of a query-param token?
// The Swift WebSocket server (`WebSocketServerAuthTests`) enforces the token
// via `Sec-WebSocket-Protocol: wolfwave.token.<hex>`. Query-param tokens are
// fine for the HTTP page fetch but not for the WS upgrade itself.
const injectedToken = "__WOLFWAVE_TOKEN__";
const wsToken =
  params.get("token") ||
  (injectedToken.indexOf("__") === 0 ? "" : injectedToken);

const RECONNECT_BASE_MS = 1000;          // first reconnect at 1s
const RECONNECT_MAX_MS = 15_000;         // ceiling so we don't back off forever
const ENTER_DURATION_MS = 600;
const EXIT_DURATION_MS = 500;
const SWAP_HALF_MS = 140;                // 1/2 of total 280ms swap budget

// Design-system token shim. Identical shape to what `generate.ts` emits, used
// only when the generated bundle didn't load (defensive).
const WW_TOKENS: WWTokens =
  (typeof window !== "undefined" && window.WW_TOKENS) || ({} as WWTokens);

const themePresets: Record<string, ThemePreset> = WW_TOKENS.themes || {
  Default: {
    containerBg: "transparent",
    containerBorder: "none",
    containerShadow: "none",
    containerRadius: "12px",
    backdropFilter: "none",
    overlayBg: "rgba(0,0,0,0.50)",
    textPrimary: "#FFFFFF",
    textSecondary: "rgba(255,255,255,0.90)",
    textMuted: "rgba(255,255,255,0.70)",
    textShadow: "none",
    progressTrackBg: "rgba(255,255,255,0.20)",
    progressFillBg: "#FFFFFF",
    showArtworkBlur: true,
  },
};

const layoutDimensions: Record<string, LayoutDims> = WW_TOKENS.layouts || {
  Horizontal: { maxWidth: 500, height: 100 },
  Vertical: { maxWidth: 220, height: 280 },
  Compact: { maxWidth: 350, height: 56 },
};

// Default config for `widget_config` messages. The native app pushes this
// shortly after `welcome` so we don't usually render with these values.
const defaultConfig: WidgetConfig = {
  theme: "Default",
  layout: "Horizontal",
  textColor: "#FFFFFF",
  backgroundColor: "#1A1A2E",
  fontFamily: "System Default",
};

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  STATE                                                                 ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  All mutable state lives here in module scope. Kept flat (not a class) on
 *  purpose — this file ships as a tiny IIFE inside one HTML page.
 *
 *  Vital invariants:
 *    • `nowPlaying` is null until the first now_playing arrives.
 *    • `elapsedRef.timestamp` is wall-clock ms; we interpolate against it.
 *    • `visible` mirrors which container class is active (single source of
 *      truth for the transition state machine).
 */

let nowPlaying: NowPlaying | null = null;
let widgetConfig: WidgetConfig = { ...defaultConfig };
let elapsed = 0;
let elapsedRef: ElapsedRef = { value: 0, timestamp: 0, isPlaying: false };
let visible = false;
let rafId: number | null = null;
let hideTimer: number | null = null;
let exitTimer: number | null = null;
let ws: WebSocket | null = null;
let reconnectTimer: number | null = null;
let reconnectAttempts = 0;
let hasReceivedTrack = false;

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  TYPES                                                                 ║
 * ╚════════════════════════════════════════════════════════════════════════╝ */

interface NowPlaying {
  track: string;
  artist: string;
  album: string;
  duration: number;
  elapsed: number;
  isPlaying: boolean;
  artworkURL?: string | null;
}

interface ElapsedRef {
  value: number;
  timestamp: number;
  isPlaying: boolean;
}

interface WidgetConfig {
  theme: string;
  layout: string;
  textColor: string;
  backgroundColor: string;
  fontFamily: string;
}

interface ThemePreset {
  containerBg: string;
  containerBorder: string;
  containerShadow: string;
  containerRadius: string;
  backdropFilter: string;
  overlayBg: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  textShadow: string;
  progressTrackBg: string;
  progressFillBg: string;
  showArtworkBlur: boolean;
  fontFamily?: string;
}

interface LayoutDims {
  maxWidth: number;
  height: number;
}

interface WWTokens {
  themes?: Record<string, ThemePreset>;
  layouts?: Record<string, LayoutDims>;
}

type WSMessage =
  | { type: "now_playing"; data: NowPlaying }
  | { type: "progress"; data: { elapsed: number; duration: number; isPlaying: boolean } }
  | { type: "playback_state"; data: { isPlaying: boolean; track?: string; artist?: string; album?: string } }
  | { type: "widget_config"; data: Partial<WidgetConfig> }
  | { type: "welcome" };

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  HELPERS                                                               ║
 * ╚════════════════════════════════════════════════════════════════════════╝ */

function formatTime(secs: number): string {
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return m + ":" + String(s).padStart(2, "0");
}

/**
 * HTML-escape user-supplied strings (track/artist/album come from Music.app
 * metadata, which is effectively untrusted). Replaces `& < > "` with entities.
 * NOT a full sanitizer — only safe inside text nodes, not URLs or attributes
 * outside the four covered chars.
 */
function escapeHtml(str: string): string {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function resolveFontFamily(name: string | undefined): string {
  if (!name || name === "System Default" || name === "System") {
    return '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  }
  return '"' + name + '", sans-serif';
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  THEME + LAYOUT                                                        ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  resolveTheme() merges a preset with user overrides (only Default/Glass
 *  themes accept overrides — the others are author-curated and stay opaque).
 */

function resolveTheme(config: WidgetConfig): ThemePreset {
  const preset = themePresets[config.theme] || themePresets["Default"];
  const resolved: ThemePreset = { ...preset };
  resolved.fontFamily = resolveFontFamily(config.fontFamily);
  if (config.theme === "Default" || config.theme === "Glass") {
    if (config.textColor && config.textColor !== defaultConfig.textColor) {
      resolved.textPrimary = config.textColor;
      resolved.textSecondary = config.textColor;
      resolved.progressFillBg = config.textColor;
    }
    if (
      config.backgroundColor &&
      config.backgroundColor !== defaultConfig.backgroundColor
    ) {
      resolved.overlayBg = config.backgroundColor;
    }
  }
  return resolved;
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  PROGRESS LOOP                                                         ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  Why interpolate client-side instead of trusting per-tick server pushes?
 *  The server emits `progress` at ~1Hz to save bandwidth, but the progress
 *  fill needs to look smooth (60Hz). We anchor on the latest server elapsed
 *  + wall-clock and let RAF fill in the gaps.
 *
 *  Formula:   elapsed = elapsedRef.value + (Date.now() - elapsedRef.timestamp) / 1000
 *
 *  When the server sends a new `progress` we re-anchor so any drift is
 *  corrected immediately on the next frame.
 */

function startProgressLoop(): void {
  if (rafId !== null) cancelAnimationFrame(rafId);
  function tick() {
    const ref = elapsedRef;
    if (ref.isPlaying && ref.timestamp > 0) {
      elapsed = ref.value + (Date.now() - ref.timestamp) / 1000;
    }
    updateProgress();
    rafId = requestAnimationFrame(tick);
  }
  rafId = requestAnimationFrame(tick);
}

function stopProgressLoop(): void {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  TRANSITIONS                                                           ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  Container: enterWidget() / exitWidget() drive the four-state machine.
 *  Inner:     swapInner() runs the .track-meta + .artwork crossfade for
 *             track-change-while-visible. It DOES NOT touch the container.
 *
 *  Why double-RAF in enterWidget()?
 *  Setting `.widget-entering` then immediately swapping to `.widget-visible`
 *  in the same frame collapses the transition (no starting frame). The first
 *  RAF lets the browser commit `entering` styles, the second begins the
 *  transition into `visible`.
 */

function enterWidget(): void {
  visible = true;
  const el = document.getElementById("widget");
  if (!el) return;

  if (exitTimer !== null) {
    clearTimeout(exitTimer);
    exitTimer = null;
  }

  el.classList.remove("placeholder");
  el.classList.remove("widget-exiting");
  el.classList.remove("widget-visible");
  el.classList.add("widget-entering");

  // Double-RAF so the starting frame commits before we begin animating.
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      el.classList.remove("widget-entering");
      el.classList.add("widget-visible");
    });
  });

  if (hideTimer !== null) clearTimeout(hideTimer);
  if (autohide > 0) {
    hideTimer = window.setTimeout(() => exitWidget(), autohide * 1000);
  }
}

function exitWidget(): void {
  if (!visible) return;
  visible = false;
  const el = document.getElementById("widget");
  if (!el) return;

  el.classList.remove("widget-visible");
  el.classList.add("widget-exiting");

  // Drain progress bar so it doesn't look frozen mid-way during the fade.
  const fill = document.querySelector(".progress-fill") as HTMLElement | null;
  if (fill) {
    fill.classList.add("draining");
    fill.style.width = "0%";
  }

  if (exitTimer !== null) clearTimeout(exitTimer);
  exitTimer = window.setTimeout(() => {
    el.classList.remove("widget-exiting");
    el.classList.add("widget-hidden");
  }, EXIT_DURATION_MS);
}

/**
 * Crossfade .track-meta + .artwork between two renders. Runs only when
 * a new track arrives while the container is already visible — keeps the
 * stream calm during rapid skips.
 */
function swapInner(rebuild: () => void): void {
  const meta = document.querySelector(".track-meta") as HTMLElement | null;
  const art = document.querySelector(".artwork") as HTMLElement | null;

  // Nothing mounted yet → just rebuild.
  if (!meta && !art) {
    rebuild();
    return;
  }

  meta?.classList.add("swap-out");
  art?.classList.add("swap-out");

  setTimeout(() => {
    rebuild();
    // The DOM is fresh after rebuild — re-query.
    const newMeta = document.querySelector(".track-meta") as HTMLElement | null;
    const newArt = document.querySelector(".artwork") as HTMLElement | null;
    newMeta?.classList.add("swap-in");
    newArt?.classList.add("swap-in");
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        newMeta?.classList.remove("swap-in");
        newArt?.classList.remove("swap-in");
      });
    });
  }, SWAP_HALF_MS);
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  RENDER                                                                ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  updateProgress() — runs every RAF frame; touches text + width only.
 *  buildWidget()    — full innerHTML rebuild on track change OR config change.
 *
 *  Why innerHTML? The widget is small and themes can change everything
 *  (layout, colors, decorative layers). A diffing renderer would cost more
 *  code than the entire file.
 */

function updateProgress(): void {
  if (!nowPlaying) return;
  const duration = nowPlaying.duration || 0;
  const progress = duration > 0 ? Math.min((elapsed / duration) * 100, 100) : 0;
  const remaining = duration > 0 ? Math.max(duration - elapsed, 0) : 0;
  const fill = document.querySelector(".progress-fill") as HTMLElement | null;
  const elapsedEl = document.querySelector(".elapsed-time");
  const remainingEl = document.querySelector(".remaining-time");
  if (fill && !fill.classList.contains("draining")) {
    fill.style.width = progress + "%";
  }
  if (elapsedEl) elapsedEl.textContent = formatTime(elapsed);
  if (remainingEl) remainingEl.textContent = "-" + formatTime(remaining);
}

function buildWidget(): void {
  if (!nowPlaying) return;
  const el = document.getElementById("widget");
  if (!el) return;

  const theme = resolveTheme(widgetConfig);
  const layout = widgetConfig.layout || "Horizontal";
  const dims = layoutDimensions[layout] || layoutDimensions["Horizontal"];
  const duration = nowPlaying.duration || 0;
  const progress = duration > 0 ? Math.min((elapsed / duration) * 100, 100) : 0;
  const remaining = duration > 0 ? Math.max(duration - elapsed, 0) : 0;

  // Container styles. We write theme-driven values inline (the themes are
  // runtime-swappable, so utility classes can't pre-compile them).
  el.style.maxWidth = dims.maxWidth + "px";
  el.style.height = dims.height + "px";
  el.style.background = theme.containerBg;
  el.style.border = theme.containerBorder;
  el.style.boxShadow = theme.containerShadow;
  el.style.borderRadius = theme.containerRadius;
  el.style.backdropFilter = theme.backdropFilter;

  /**
   * Render the artwork — either the iTunes Search URL or a WolfWave-branded
   * SVG fallback (wolf mark on brand-blue gradient). Keep the SVG in sync
   * with Assets.xcassets/WolfMark.imageset/WolfMark.svg.
   */
  function artImg(w: number, h: number, radius: string): string {
    let artURL = nowPlaying!.artworkURL || null;
    if (artURL && !artURL.startsWith("http://") && !artURL.startsWith("https://")) {
      artURL = null;
    }
    if (!artURL) {
      const mark = Math.round(w * 0.52);
      return (
        '<div class="artwork flex items-center justify-center" style="width:' + w + "px;height:" + h + "px;border-radius:" + radius + ";background:linear-gradient(135deg,#0A84FF,#003A78);box-shadow:0 2px 8px rgba(0,0,0,0.3);\">" +
        '<svg width="' + mark + '" height="' + mark + '" viewBox="0 0 100 100" fill="#FFFFFF">' +
        '<rect x="24" y="43" width="3.5" height="30" rx="1.75"/>' +
        '<rect x="19" y="49" width="3.5" height="24" rx="1.75" opacity="0.9"/>' +
        '<rect x="14" y="55" width="3.5" height="18" rx="1.75" opacity="0.73"/>' +
        '<rect x="9" y="61" width="3.5" height="12" rx="1.75" opacity="0.54"/>' +
        '<rect x="4" y="66" width="3.5" height="7" rx="1.75" opacity="0.34"/>' +
        '<rect x="-1" y="69" width="3.5" height="4" rx="1.75" opacity="0.18"/>' +
        '<rect x="72.5" y="43" width="3.5" height="30" rx="1.75"/>' +
        '<rect x="77.5" y="49" width="3.5" height="24" rx="1.75" opacity="0.9"/>' +
        '<rect x="82.5" y="55" width="3.5" height="18" rx="1.75" opacity="0.73"/>' +
        '<rect x="87.5" y="61" width="3.5" height="12" rx="1.75" opacity="0.54"/>' +
        '<rect x="92.5" y="66" width="3.5" height="7" rx="1.75" opacity="0.34"/>' +
        '<rect x="97.5" y="69" width="3.5" height="4" rx="1.75" opacity="0.18"/>' +
        '<polygon points="33,41 33,11 45,38"/>' +
        '<polygon points="67,41 67,11 55,38"/>' +
        '<ellipse cx="50" cy="52" rx="18" ry="17.5"/>' +
        '<ellipse cx="50" cy="63" rx="11" ry="8"/>' +
        "</svg>" +
        "</div>"
      );
    }
    // Encode the URL once. Music.app artwork is iTunes CDN, but a malicious
    // mock server could theoretically send a quote in the URL — encode it.
    const safeURL = encodeURI(artURL).replace(/'/g, "%27").replace(/"/g, "%22");
    return (
      '<img class="artwork" src="' + safeURL + '" crossorigin="anonymous" ' +
      'style="width:' + w + "px;height:" + h + "px;border-radius:" + radius + ";object-fit:cover;box-shadow:0 2px 8px rgba(0,0,0,0.3);\">"
    );
  }

  const barH = layout === "Vertical" ? "3px" : "4px";
  const timeSize = layout === "Vertical" ? "9px" : "10px";
  const fillStyle =
    "width:" + progress + "%;background:" + theme.progressFillBg + ";height:100%;border-radius:9999px;";

  const progressBar =
    '<div class="progress-track" style="background:' + theme.progressTrackBg + ";height:" + barH + ';">' +
    '<div class="progress-fill" style="' + fillStyle + '"></div>' +
    "</div>" +
    '<div class="time-row">' +
    '<span class="elapsed-time" style="color:' + theme.textMuted + ";font-family:" + theme.fontFamily + ";font-size:" + timeSize + ';">' + formatTime(elapsed) + "</span>" +
    '<span class="remaining-time" style="color:' + theme.textMuted + ";font-family:" + theme.fontFamily + ";font-size:" + timeSize + ';">-' + formatTime(remaining) + "</span>" +
    "</div>";

  const validArtworkURL =
    !!nowPlaying.artworkURL &&
    (nowPlaying.artworkURL.startsWith("http://") || nowPlaying.artworkURL.startsWith("https://"));
  const safeBlurURL = validArtworkURL
    ? encodeURI(nowPlaying.artworkURL!).replace(/'/g, "%27").replace(/"/g, "%22").replace(/\)/g, "%29")
    : "";
  const blurLayer =
    theme.showArtworkBlur && validArtworkURL
      ? '<div class="blur-layer" style="background-image:url(' + safeBlurURL + ');"></div>'
      : "";
  const overlayLayer =
    theme.overlayBg && theme.overlayBg !== "transparent"
      ? '<div class="overlay-layer" style="background:' + theme.overlayBg + ';"></div>'
      : "";
  const noiseLayer = '<div class="noise-layer"></div>';

  let layoutHTML = "";
  if (layout === "Horizontal") {
    const art = hideAlbumArt
      ? ""
      : '<div style="flex-shrink:0;padding:5px;">' + artImg(90, 90, "10px") + "</div>";
    layoutHTML =
      '<div class="flex h-full">' +
      art +
      '<div style="display:flex;flex-direction:column;flex:1;min-width:0;justify-content:center;padding:8px 12px 8px 0;">' +
      '<div class="track-meta" style="min-width:0;">' +
      '<p style="font-size:18px;font-weight:700;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:' + theme.textPrimary + ";text-shadow:" + theme.textShadow + ";font-family:" + theme.fontFamily + ';">' + escapeHtml(nowPlaying.track) + "</p>" +
      '<p style="font-size:13px;font-style:italic;font-weight:300;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:' + theme.textSecondary + ";text-shadow:" + theme.textShadow + ";font-family:" + theme.fontFamily + ';">' + escapeHtml(nowPlaying.artist) + "</p>" +
      "</div>" +
      '<div style="display:flex;align-items:center;margin-top:auto;gap:6px;">' +
      '<div style="flex:1;min-width:0;">' + progressBar + "</div>" +
      "</div>" +
      "</div>" +
      "</div>";
  } else if (layout === "Vertical") {
    const art = hideAlbumArt ? "" : '<div class="shrink-0">' + artImg(200, 200, "10px") + "</div>";
    layoutHTML =
      '<div class="flex-col h-full items-center" style="padding:8px;">' +
      art +
      '<div class="track-meta" style="display:flex;flex-direction:column;flex:1;min-width:0;width:100%;align-items:center;justify-content:center;margin-top:4px;">' +
      '<p style="font-size:13px;font-weight:700;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;color:' + theme.textPrimary + ";text-shadow:" + theme.textShadow + ";font-family:" + theme.fontFamily + ';">' + escapeHtml(nowPlaying.track) + "</p>" +
      '<p style="font-size:11px;font-style:italic;font-weight:300;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;color:' + theme.textSecondary + ";text-shadow:" + theme.textShadow + ";font-family:" + theme.fontFamily + ';">' + escapeHtml(nowPlaying.artist) + "</p>" +
      "</div>" +
      '<div style="width:100%;padding:0 4px;margin-top:auto;">' + progressBar + "</div>" +
      "</div>";
  } else {
    const art = hideAlbumArt
      ? ""
      : '<div style="flex-shrink:0;padding:5px;">' + artImg(46, 46, "8px") + "</div>";
    layoutHTML =
      '<div class="flex h-full items-center" style="padding:0 4px;">' +
      art +
      '<div class="track-meta" style="flex:1;min-width:0;padding:0 8px;">' +
      '<p style="font-size:13px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:' + theme.textPrimary + ";text-shadow:" + theme.textShadow + ";font-family:" + theme.fontFamily + ';">' +
      escapeHtml(nowPlaying.track) +
      '<span style="color:' + theme.textMuted + ';"> — </span>' +
      '<span style="color:' + theme.textSecondary + ';">' + escapeHtml(nowPlaying.artist) + "</span>" +
      "</p>" +
      "</div>" +
      "</div>";
  }

  el.innerHTML = blurLayer + overlayLayer + noiseLayer + '<div class="relative h-full">' + layoutHTML + "</div>";
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  WEBSOCKET                                                             ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  Reconnect: exponential backoff capped at RECONNECT_MAX_MS.
 *      delay = min(BASE * 2^(n-1), MAX)
 *  Prevents a hammered server from getting hit harder when something is
 *  already wrong (matches the cadence the native app reconnects to Twitch).
 */

function connect(): void {
  if (ws) return;
  const wsHost = location.hostname || "localhost";
  const wsURL = "ws://" + wsHost + ":" + wsPort;
  console.log("[WolfWave Widget] Connecting to " + wsURL);
  const protocols = wsToken ? ["wolfwave.token." + wsToken] : [];
  ws = new WebSocket(wsURL, protocols);

  ws.onopen = () => {
    console.log("[WolfWave Widget] Connected to " + wsURL);
    reconnectAttempts = 0;
  };

  ws.onmessage = (event) => {
    try {
      handleMessage(JSON.parse(event.data) as WSMessage);
    } catch (e) {
      console.warn("[WolfWave Widget] Failed to parse message:", e);
    }
  };

  ws.onclose = () => {
    ws = null;
    nowPlaying = null;
    hasReceivedTrack = false;
    stopProgressLoop();
    exitWidget();
    reconnectAttempts++;
    const delay = Math.min(
      RECONNECT_BASE_MS * Math.pow(2, reconnectAttempts - 1),
      RECONNECT_MAX_MS,
    );
    console.log("[WolfWave Widget] Disconnected — reconnect in " + delay + "ms (attempt " + reconnectAttempts + ")");
    if (reconnectTimer !== null) clearTimeout(reconnectTimer);
    reconnectTimer = window.setTimeout(connect, delay);
  };

  ws.onerror = (e) => {
    console.warn("[WolfWave Widget] WebSocket error:", e);
  };
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  MESSAGE HANDLERS                                                      ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  One case per server message type. Schemas locked by Swift tests — adding
 *  fields server-side is safe; renaming fields requires a server-coordinated
 *  change. See `WebSocketServerService.swift` lines 522–563.
 */

function isSameTrack(a: NowPlaying | null, b: { track?: string; artist?: string }): boolean {
  if (!a) return false;
  return a.track === b.track && a.artist === b.artist;
}

function handleMessage(msg: WSMessage): void {
  switch (msg.type) {
    case "now_playing": {
      const data = msg.data;
      const sameTrack = isSameTrack(nowPlaying, data);
      nowPlaying = data;
      elapsedRef = { value: data.elapsed, timestamp: Date.now(), isPlaying: data.isPlaying };
      elapsed = data.elapsed;
      hasReceivedTrack = true;

      if (visible && !sameTrack) {
        // New track while card is on stream — crossfade inner only.
        swapInner(buildWidget);
      } else {
        buildWidget();
      }

      if (data.isPlaying) {
        if (!visible) enterWidget();
        startProgressLoop();
      }
      break;
    }
    case "progress": {
      const data = msg.data;
      // Re-anchor interpolation. Defends against clock drift on long tracks.
      elapsedRef = { value: data.elapsed, timestamp: Date.now(), isPlaying: data.isPlaying };
      break;
    }
    case "playback_state": {
      const data = msg.data;
      if (nowPlaying) Object.assign(nowPlaying, data);
      if (!data.isPlaying) {
        // Freeze elapsed at current computed value so resume doesn't jump.
        elapsedRef = { value: elapsed, timestamp: Date.now(), isPlaying: false };
        stopProgressLoop();
        exitWidget();
      } else {
        elapsedRef = { value: elapsed, timestamp: Date.now(), isPlaying: true };
        if (!visible) enterWidget();
        startProgressLoop();
      }
      break;
    }
    case "widget_config": {
      widgetConfig = { ...defaultConfig, ...(msg.data as WidgetConfig) };
      buildWidget();
      break;
    }
    case "welcome":
      reconnectAttempts = 0;
      if (!hasReceivedTrack) {
        console.log("[WolfWave Widget] Connected, waiting for music...");
      }
      break;
  }
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  BOOT                                                                  ║
 * ╚════════════════════════════════════════════════════════════════════════╝ */

// Make sure the container starts in the hidden state so the first enter
// animation has a clean starting frame to transition from.
(function boot() {
  const el = document.getElementById("widget");
  if (el && !el.classList.contains("placeholder")) {
    el.classList.add("widget-hidden");
  }
  connect();
})();

export {};

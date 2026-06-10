/* ═══════════════════════════════════════════════════════════════════════════
 *  WolfWave OBS Widget - Runtime
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
 *    • Never re-trigger the bouncy entrance on every track skip - instead
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
    // In-app Settings preview bridge. Defined only in preview mode (see
    // `setupPreview`). The native `WidgetAppearancePreview` (WKWebView) drives
    // the real renderer through this hook instead of a WebSocket feed, so the
    // settings preview is pixel-identical to the live overlay.
    WWPreview?: {
      config(cfg: Partial<WidgetConfig>): void;
      track(t: Partial<NowPlaying>): void;
    };
    // Set to `true` by the native preview host via a document-start user script,
    // before this bundle runs. Switches the boot path from WebSocket to preview.
    __WW_PREVIEW__?: boolean;
  }
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  CONFIG / FALLBACKS                                                    ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  URL-derived config + the design-system fallback shim. The shim only kicks
 *  in if `widget-tokens.generated.js` failed to load (file:// or stale build),
 *  so the widget never throws - it falls back to the Default theme/layout.
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
 *  purpose - this file ships as a tiny IIFE inside one HTML page.
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
  // Clamp negative/NaN input (a mid-stream elapsed glitch) to 0:00. Mirrors
  // the docs site's shared `lib/format-time.ts`; this copy stays local because
  // the widget compiles to a self-contained committed artifact.
  const safe = Math.max(0, Math.floor(secs)) || 0;
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  return m + ":" + String(s).padStart(2, "0");
}

/**
 * HTML-escape user-supplied strings (track/artist/album come from Music.app
 * metadata, which is effectively untrusted). Replaces `& < > " '` with
 * entities. NOT a full sanitizer - only safe inside text nodes and quoted
 * attribute values, not in URLs or unquoted attribute contexts.
 */
function escapeHtml(str: string): string {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Allowlist of CSS color keywords the config may use besides the regex forms.
 * Anything outside this set plus the hex/rgb/hsl regex below is rejected so a
 * malicious `widget_config` cannot inject a value that breaks out of the
 * inline `style="…"` attributes we concatenate at render time.
 */
const NAMED_COLORS = new Set([
  "transparent",
  "currentcolor",
  "inherit",
  "black",
  "white",
  "red",
  "green",
  "blue",
  "yellow",
  "orange",
  "purple",
  "pink",
  "gray",
  "grey",
  "cyan",
  "magenta",
  "none",
]);

// Strict CSS color shapes: #rgb / #rgba / #rrggbb / #rrggbbaa, rgb()/rgba(),
// hsl()/hsla(). No url(), no semicolons, no quotes - those can't appear here.
const COLOR_RE =
  /^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$|^rgba?\(\s*[\d.,%\s/]+\)$|^hsla?\(\s*[\d.,%\s/deg]+\)$/i;

/**
 * Validate a config-supplied color against the allowlist. Returns the trimmed
 * value when safe, otherwise `null` so the caller falls back to the preset.
 */
function safeColor(value: string | undefined): string | null {
  if (!value) return null;
  const v = value.trim();
  if (v.length === 0 || v.length > 64) return null;
  if (NAMED_COLORS.has(v.toLowerCase())) return v;
  if (COLOR_RE.test(v)) return v;
  return null;
}

function resolveFontFamily(name: string | undefined): string {
  if (!name || name === "System Default" || name === "System") {
    return '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  }
  // Strip double-quotes (and any chars that could break out of the quoted
  // family name or the inline style attribute) before wrapping in quotes.
  const cleaned = name.replace(/["';{}<>]/g, "").trim();
  if (cleaned.length === 0) {
    return '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
  }
  return '"' + cleaned + '", sans-serif';
}

/* ╔════════════════════════════════════════════════════════════════════════╗
 * ║  THEME + LAYOUT                                                        ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  resolveTheme() merges a preset with user overrides. Only the themes whose
 *  native settings UI exposes the color pickers accept overrides. The others
 *  are author-curated and stay opaque.
 */

// Themes whose text/background colors the user can override. Mirrors the
// `customizable` set in `design-system/scripts/generate.ts` (which drives the
// native `userCustomizable` flag that enables/disables the color pickers). Keep
// these in sync. (The native "Default, Glass, and WolfWave …" picker caption is
// stale; the actual gate excludes WolfWave, so the widget excludes it too.)
const THEMES_ALLOWING_OVERRIDE = new Set(["Default", "Glass"]);

function resolveTheme(config: WidgetConfig): ThemePreset {
  const preset = themePresets[config.theme] || themePresets["Default"];
  const resolved: ThemePreset = { ...preset };
  // The font stack contains double quotes (e.g. `"Segoe UI"`); buildWidget
  // splices `theme.fontFamily` straight into double-quoted `style="…"`
  // attributes via innerHTML, so escape it here. The browser unescapes the
  // entities when it parses the attribute, so the rendered font is unchanged.
  resolved.fontFamily = escapeHtml(resolveFontFamily(config.fontFamily));
  if (THEMES_ALLOWING_OVERRIDE.has(config.theme)) {
    // NOTE: the `widget_config` wire format carries no presence info. The
    // native server (`WebSocketServerService.swift`) always sends `textColor`
    // and `backgroundColor`, defaulting to `defaultConfig` values when the user
    // hasn't picked one, and `handleMessage` back-fills any missing field from
    // `defaultConfig`. So "did the user actually choose this color?" can't be
    // answered here without a contract change (a separate "color was set" flag,
    // or sending the field only when chosen). Until that lands we keep the
    // default-equality heuristic: a value equal to the default is treated as
    // "unset" and falls back to the preset. This means a deliberate selection
    // that equals the default (e.g. white text on Glass) is not applied (a
    // known limitation). Dropping the check instead would regress Default's
    // overlay to opaque `#1A1A2E` for every uncustomized user, which is worse.
    const textColor = safeColor(config.textColor);
    if (textColor && textColor !== defaultConfig.textColor) {
      resolved.textPrimary = textColor;
      resolved.textSecondary = textColor;
      resolved.progressFillBg = textColor;
    }
    const bgColor = safeColor(config.backgroundColor);
    if (bgColor && bgColor !== defaultConfig.backgroundColor) {
      resolved.overlayBg = bgColor;
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
 * a new track arrives while the container is already visible - keeps the
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
    // The DOM is fresh after rebuild - re-query.
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
 *  updateProgress() - runs every RAF frame; touches text + width only.
 *  buildWidget()    - full innerHTML rebuild on track change OR config change.
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
  // Paused affordance: track stays on stream but artwork dims and a pause
  // glyph overlays the album art. CSS keys off the `.is-paused` root class.
  const isPaused = nowPlaying.isPlaying === false;
  el.classList.toggle("is-paused", isPaused);

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
   * Render the artwork - either the iTunes Search URL or a WolfWave-branded
   * SVG fallback (wolf mark on brand-blue gradient). Keep the SVG in sync
   * with Assets.xcassets/WolfMark.imageset/WolfMark.svg.
   */
  function pauseOverlay(w: number, radius: string): string {
    const glyph = Math.max(Math.round(w * 0.42), 18);
    return (
      '<div class="pause-overlay" aria-hidden="true" style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;border-radius:' + radius + ';pointer-events:none;">' +
      '<div class="pause-overlay-bg" style="width:' + glyph + "px;height:" + glyph + 'px;border-radius:9999px;background:rgba(0,0,0,0.55);backdrop-filter:blur(6px);display:flex;align-items:center;justify-content:center;">' +
      '<svg width="' + Math.round(glyph * 0.55) + '" height="' + Math.round(glyph * 0.55) + '" viewBox="0 0 24 24" fill="#FFFFFF">' +
      '<rect x="6" y="5" width="4" height="14" rx="1.2"/>' +
      '<rect x="14" y="5" width="4" height="14" rx="1.2"/>' +
      "</svg>" +
      "</div>" +
      "</div>"
    );
  }

  function artImg(w: number, h: number, radius: string): string {
    let artURL = nowPlaying!.artworkURL || null;
    if (artURL && !artURL.startsWith("http://") && !artURL.startsWith("https://")) {
      artURL = null;
    }
    const wrapOpen = '<div class="artwork-wrap" style="position:relative;display:inline-block;width:' + w + "px;height:" + h + 'px;">';
    const wrapClose = pauseOverlay(w, radius) + "</div>";
    if (!artURL) {
      const mark = Math.round(w * 0.52);
      return (
        wrapOpen +
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
        "</div>" +
        wrapClose
      );
    }
    // Encode the URL once. Music.app artwork is iTunes CDN, but a malicious
    // mock server could theoretically send a quote in the URL - encode it.
    const safeURL = encodeURI(artURL).replace(/'/g, "%27").replace(/"/g, "%22");
    const altText = escapeHtml(nowPlaying!.album || nowPlaying!.track || "Album artwork");
    return (
      wrapOpen +
      '<img class="artwork" src="' + safeURL + '" alt="' + altText + '" crossorigin="anonymous" ' +
      'style="width:' + w + "px;height:" + h + "px;border-radius:" + radius + ";object-fit:cover;box-shadow:0 2px 8px rgba(0,0,0,0.3);\">" +
      wrapClose
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
      '<div class="flex flex-col h-full items-center" style="padding:8px;">' +
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
      '<span style="color:' + theme.textMuted + ';"> · </span>' +
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
    console.log("[WolfWave Widget] Disconnected - reconnect in " + delay + "ms (attempt " + reconnectAttempts + ")");
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
 *  One case per server message type. Schemas locked by Swift tests - adding
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
        // New track while card is on stream - crossfade inner only.
        swapInner(buildWidget);
      } else {
        buildWidget();
      }

      // Show the card whether the track is playing OR paused - paused tracks
      // still belong on stream with a paused affordance. `exitWidget` only
      // fires from the server-driven "track cleared" path.
      if (!visible) enterWidget();
      if (data.isPlaying) {
        startProgressLoop();
      } else {
        stopProgressLoop();
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
      if (!data.isPlaying) {
        // The server only emits `playback_state { isPlaying: false }` when
        // playback has fully stopped - Music.app quit, permission revoked, or
        // the source errored (`WebSocketServerService.clearNowPlaying`). A
        // *pause* arrives as a `now_playing` message with `isPlaying: false`
        // instead, so this branch always means "nothing is playing" and the
        // overlay should leave the stream rather than linger on the last track.
        nowPlaying = null;
        elapsedRef = { value: 0, timestamp: Date.now(), isPlaying: false };
        stopProgressLoop();
        exitWidget();
      } else {
        if (nowPlaying) Object.assign(nowPlaying, data);
        elapsedRef = { value: elapsed, timestamp: Date.now(), isPlaying: true };
        if (!visible) enterWidget();
        buildWidget();
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
 * ║  PREVIEW BRIDGE                                                        ║
 * ╚════════════════════════════════════════════════════════════════════════╝
 *
 *  In-app Settings preview. The native `WidgetAppearancePreview` loads this
 *  exact file in a WKWebView so the preview and the live OBS overlay are the
 *  same renderer (no parallel SwiftUI mock to drift out of sync). There is no
 *  WebSocket in preview mode - the host drives the card directly:
 *
 *    window.WWPreview.track(sampleTrack)   // once, after load
 *    window.WWPreview.config(draftConfig)  // on every appearance edit
 *
 *  Differences from the live path, all deliberate:
 *    • No `connect()` - no socket, no reconnect backoff noise.
 *    • The progress loop never starts, so the card holds a single static frame
 *      instead of advancing/elapsing while the user tweaks settings.
 *    • `#root` gets a checkerboard via the `ww-preview` body class so the
 *      transparent Default theme reads as transparent (matches the stage the
 *      old SwiftUI mock drew).
 */

function isPreview(): boolean {
  return (
    params.has("preview") ||
    (typeof window !== "undefined" && window.__WW_PREVIEW__ === true)
  );
}

function setupPreview(): void {
  document.body.classList.add("ww-preview");

  const el = document.getElementById("widget");
  if (el) {
    // Drop the "Waiting for music…" placeholder and start hidden so the first
    // `track()` plays the entrance once (config edits afterward don't re-bounce).
    el.classList.remove("placeholder");
    el.classList.add("widget-hidden");
  }

  window.WWPreview = {
    config(cfg: Partial<WidgetConfig>): void {
      widgetConfig = { ...defaultConfig, ...cfg };
      if (nowPlaying) buildWidget();
    },
    track(t: Partial<NowPlaying>): void {
      nowPlaying = {
        track: t.track || "",
        artist: t.artist || "",
        album: t.album || "",
        duration: t.duration || 0,
        elapsed: t.elapsed || 0,
        // Keep `isPlaying` truthy so the paused affordance (dimmed art + glyph)
        // never shows in a preview; we just don't run the progress loop.
        isPlaying: t.isPlaying !== false,
        artworkURL: t.artworkURL || null,
      };
      elapsed = nowPlaying.elapsed;
      elapsedRef = { value: elapsed, timestamp: 0, isPlaying: false };
      buildWidget();
      if (!visible) enterWidget();
    },
  };
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
  if (isPreview()) {
    setupPreview();
    return;
  }
  connect();
})();

export {};

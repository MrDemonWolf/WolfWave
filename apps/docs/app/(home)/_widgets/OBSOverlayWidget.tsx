"use client";

import { useState } from "react";
import { AlbumArt } from "./AlbumArt";
import { formatTime } from "@/lib/format-time";
import { useCyclingTrack, cyclingPauseHandlers } from "./useCyclingTrack";
import {
  WIDGET_THEMES,
  WIDGET_LAYOUTS,
  USER_THEMES,
  DEFAULT_THEME,
  DEFAULT_LAYOUT,
  type WidgetThemeName,
  type WidgetLayoutName,
} from "./widget-themes.generated";

/**
 * Theme + layout data comes from `widget-themes.generated.ts`, which the
 * design-token generator emits from `design-system/tokens.json`. That keeps
 * this preview in lockstep with the native app's themes and its shipped
 * default (Default / Horizontal) instead of a hand-copied dict that drifts.
 */
type ThemeName = WidgetThemeName;
type LayoutName = WidgetLayoutName;
type ThemeVals = (typeof WIDGET_THEMES)[ThemeName];

const THEMES: ThemeName[] = USER_THEMES;
const LAYOUTS = Object.keys(WIDGET_LAYOUTS) as LayoutName[];

/**
 * Recreation of the live WolfWave OBS browser-source overlay.
 *
 * The aesthetic and theme tokens come from
 * `apps/native/WolfWave/Resources/widget.html` +
 * `widget-tokens.generated.js`. Visitor can switch layouts (Horizontal /
 * Vertical / Compact / Vinyl / Classic) and themes (WolfWave / Glass / Neon /
 * Dark / Light) right on the marketing page, selling the widget's flexibility
 * better than any static screenshot could.
 */
export function OBSOverlayWidget({ controls = true }: { controls?: boolean } = {}) {
  const [theme, setTheme] = useState<ThemeName>(DEFAULT_THEME);
  const [layout, setLayout] = useState<LayoutName>(DEFAULT_LAYOUT);

  // Hero usage: no theme/layout switcher, render only the default overlay card.
  if (!controls) {
    return (
      <div style={{ width: "100%" }}>
        <WidgetCard theme={WIDGET_THEMES[DEFAULT_THEME]} layout={DEFAULT_LAYOUT} />
      </div>
    );
  }

  return (
    <div style={{ width: "100%" }} {...cyclingPauseHandlers()}>
      <ControlBar
        theme={theme}
        layout={layout}
        onThemeChange={setTheme}
        onLayoutChange={setLayout}
      />
      <div
        style={{
          minHeight: layout === "Vertical" || layout === "Vinyl" ? 340 : 160,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: 16,
        }}
      >
        <WidgetCard theme={WIDGET_THEMES[theme]} layout={layout} />
      </div>
      <span className="sr-only">
        Interactive widget preview cycling fictional sample tracks. Use the
        layout and theme controls above to preview every combination.
      </span>
    </div>
  );
}

function WidgetCard({
  theme,
  layout,
}: {
  theme: ThemeVals;
  layout: LayoutName;
}) {
  const { track, elapsedSec, progress, motionEnabled } = useCyclingTrack();

  const dims = WIDGET_LAYOUTS[layout];
  const scrim = theme.overlayBg && theme.overlayBg !== "transparent";

  const shell = {
    position: "relative" as const,
    background: theme.containerBg,
    border: theme.containerBorder,
    boxShadow: theme.containerShadow,
    borderRadius: theme.containerRadius,
    backdropFilter: theme.backdropFilter,
    WebkitBackdropFilter: theme.backdropFilter,
    color: theme.textPrimary,
    textShadow: theme.textShadow,
    fontFamily:
      "'Instrument Sans', var(--ds-font-family-sans), system-ui, sans-serif",
    overflow: "hidden" as const,
    width: "100%",
    maxWidth: dims.maxWidth,
    transition:
      "background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease, border-radius 0.25s ease",
  };

  // Transparent themes (Default) read against the OBS scene, not a card.
  // Mirror widget.html: a blurred copy of the artwork fills the frame with a
  // dark scrim over it so the text stays legible. Marketing art is a CSS
  // gradient, so we blur the gradient itself.
  const bgLayers = (
    <>
      {theme.showArtworkBlur ? (
        <div
          aria-hidden="true"
          style={{
            position: "absolute",
            inset: 0,
            background: track.gradient,
            transform: "scale(1.4)",
            filter: "blur(22px)",
            transition: "background 0.4s ease",
          }}
        />
      ) : null}
      {scrim ? (
        <div
          aria-hidden="true"
          style={{ position: "absolute", inset: 0, background: theme.overlayBg }}
        />
      ) : null}
    </>
  );

  if (layout === "Compact") {
    return (
      <div
        role="group"
        aria-roledescription="OBS overlay demo"
        style={{ ...shell, height: dims.height }}
      >
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            height: "100%",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "8px 12px",
          }}
        >
          <AlbumArt
            gradient={track.gradient}
            glyph={track.glyph}
            size={40}
            radius={6}
          />
          <div style={{ minWidth: 0, flex: 1 }}>
            <div
              style={{
                fontSize: 13,
                fontWeight: 600,
                lineHeight: 1.2,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {track.title}
            </div>
            <div
              style={{
                fontSize: 11,
                color: theme.textSecondary,
                marginTop: 1,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {track.artist}
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (layout === "Vertical") {
    return (
      <div role="group" aria-roledescription="OBS overlay demo" style={shell}>
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 12,
            padding: 14,
          }}
        >
          <AlbumArt
            gradient={track.gradient}
            glyph={track.glyph}
            size={184}
            radius={10}
          />
          <div style={{ width: "100%", textAlign: "center" }}>
            <div
              style={{
                fontSize: 14,
                fontWeight: 600,
                lineHeight: 1.25,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {track.title}
            </div>
            <div
              style={{
                fontSize: 12,
                color: theme.textSecondary,
                marginTop: 4,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {track.artist}
            </div>
          </div>
          <ProgressBar
            theme={theme}
            elapsedSec={elapsedSec}
            durationSec={track.durationSec}
            progress={progress}
            motionEnabled={motionEnabled}
            showCounters
          />
        </div>
      </div>
    );
  }

  if (layout === "Vinyl") {
    const RING_R = 94;
    const RING_C = 2 * Math.PI * RING_R;
    // An SVG stroke can't be a CSS gradient (e.g. the Neon theme's fill), so
    // render a real <linearGradient> and stroke via url() when needed.
    const ringIsGradient = /gradient/i.test(theme.progressFillBg);
    const ringCols = ringIsGradient
      ? theme.progressFillBg.match(/#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)/g) ?? ["#FFFFFF"]
      : [];
    const ringStroke = ringIsGradient ? "url(#wwVinylRingGrad)" : theme.progressFillBg;
    return (
      <div role="group" aria-roledescription="OBS overlay demo" style={shell}>
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 10,
            padding: 14,
          }}
        >
          <div style={{ position: "relative", width: 200, height: 200 }}>
            <div
              className={motionEnabled ? "ww-vinyl-spin" : undefined}
              style={{
                position: "absolute",
                inset: 0,
                borderRadius: "50%",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background:
                  "repeating-radial-gradient(circle at 50% 50%, #0a0a0a 0 2px, #171717 2px 3px), radial-gradient(circle at 38% 32%, #2c2c2c 0%, #0a0a0a 62%)",
                boxShadow:
                  "0 10px 30px rgba(0,0,0,0.55), inset 0 0 0 1px rgba(255,255,255,0.05)",
              }}
            >
              <div
                style={{
                  borderRadius: "50%",
                  boxShadow:
                    "0 0 0 3px rgba(0,0,0,0.55), 0 0 0 4px rgba(255,255,255,0.08)",
                }}
              >
                <AlbumArt
                  gradient={track.gradient}
                  glyph={track.glyph}
                  size={84}
                  radius={42}
                />
              </div>
              <div
                aria-hidden="true"
                style={{
                  position: "absolute",
                  left: "50%",
                  top: "50%",
                  width: 9,
                  height: 9,
                  transform: "translate(-50%, -50%)",
                  borderRadius: "50%",
                  background: "#060606",
                  boxShadow: "0 0 0 2px #2b2b2b",
                }}
              />
            </div>
            <svg
              viewBox="0 0 200 200"
              aria-hidden="true"
              style={{
                position: "absolute",
                inset: 0,
                width: "100%",
                height: "100%",
                transform: "rotate(-90deg)",
              }}
            >
              {ringIsGradient ? (
                <defs>
                  <linearGradient id="wwVinylRingGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                    {ringCols.map((c, i) => (
                      <stop
                        key={i}
                        offset={`${ringCols.length < 2 ? 0 : Math.round((i / (ringCols.length - 1)) * 100)}%`}
                        stopColor={c}
                      />
                    ))}
                  </linearGradient>
                </defs>
              ) : null}
              <circle
                cx="100"
                cy="100"
                r={RING_R}
                fill="none"
                strokeWidth={5}
                stroke={theme.progressTrackBg}
              />
              <circle
                cx="100"
                cy="100"
                r={RING_R}
                fill="none"
                strokeWidth={5}
                strokeLinecap="round"
                stroke={ringStroke}
                strokeDasharray={RING_C}
                strokeDashoffset={RING_C * (1 - progress)}
                style={{ transition: motionEnabled ? "stroke-dashoffset 100ms linear" : "none" }}
              />
            </svg>
          </div>
          <div style={{ width: "100%", textAlign: "center" }}>
            <div
              style={{
                fontSize: 14,
                fontWeight: 600,
                lineHeight: 1.25,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {track.title}
            </div>
            <div
              style={{
                fontSize: 12,
                color: theme.textSecondary,
                marginTop: 2,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {track.artist}
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (layout === "Classic") {
    return (
      <div
        role="group"
        aria-roledescription="OBS overlay demo"
        style={{ ...shell, height: dims.height }}
      >
        {bgLayers}
        <div
          style={{
            position: "relative",
            zIndex: 1,
            height: "100%",
            display: "grid",
            gridTemplateColumns: "92px 1fr",
            gap: 14,
            alignItems: "center",
            padding: 10,
          }}
        >
          <AlbumArt
            gradient={track.gradient}
            glyph={track.glyph}
            size={92}
            radius={14}
          />
          <div
            style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}
          >
            <div
              style={{
                fontSize: 16,
                fontWeight: 700,
                lineHeight: 1.2,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {track.title}
            </div>
            <div
              style={{
                fontSize: 13,
                color: theme.textSecondary,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {track.artist}
            </div>
            <ProgressBar
              theme={theme}
              elapsedSec={elapsedSec}
              durationSec={track.durationSec}
              progress={progress}
              motionEnabled={motionEnabled}
              showCounters
              knob
            />
          </div>
        </div>
      </div>
    );
  }

  // Horizontal (default)
  return (
    <div
      role="group"
      aria-roledescription="OBS overlay demo"
      style={{ ...shell, height: dims.height }}
    >
      {bgLayers}
      <div
        style={{
          position: "relative",
          zIndex: 1,
          height: "100%",
          display: "grid",
          gridTemplateColumns: "80px 1fr",
          gap: 12,
          alignItems: "center",
          padding: 10,
        }}
      >
        <AlbumArt
          gradient={track.gradient}
          glyph={track.glyph}
          size={80}
          radius={8}
        />
        <div
          style={{ minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}
        >
          <div
            style={{
              fontSize: 15,
              fontWeight: 600,
              lineHeight: 1.2,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.title}
          </div>
          <div
            style={{
              fontSize: 12,
              color: theme.textSecondary,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.artist}
          </div>
          <ProgressBar
            theme={theme}
            elapsedSec={elapsedSec}
            durationSec={track.durationSec}
            progress={progress}
            motionEnabled={motionEnabled}
            showCounters
          />
        </div>
      </div>
    </div>
  );
}

function ProgressBar({
  theme,
  elapsedSec,
  durationSec,
  progress,
  motionEnabled,
  showCounters,
  knob,
}: {
  theme: ThemeVals;
  elapsedSec: number;
  durationSec: number;
  progress: number;
  motionEnabled: boolean;
  showCounters?: boolean;
  knob?: boolean;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4, width: "100%" }}>
      <div
        role="progressbar"
        aria-label="Track progress"
        aria-valuemin={0}
        aria-valuemax={durationSec}
        aria-valuenow={Math.round(elapsedSec)}
        style={{
          position: "relative",
          height: knob ? 5 : 4,
          background: theme.progressTrackBg,
          borderRadius: 9999,
          overflow: knob ? "visible" : "hidden",
        }}
      >
        <div
          style={{
            position: "absolute",
            insetBlock: 0,
            left: 0,
            width: `${progress * 100}%`,
            background: theme.progressFillBg,
            borderRadius: 9999,
            transition: motionEnabled ? "width 100ms linear" : "none",
          }}
        />
        {knob ? (
          <div
            aria-hidden="true"
            style={{
              position: "absolute",
              top: "50%",
              left: `${progress * 100}%`,
              width: 11,
              height: 11,
              transform: "translate(-50%, -50%)",
              borderRadius: "50%",
              background: "#fff",
              boxShadow: "0 1px 4px rgba(0,0,0,0.5)",
              transition: motionEnabled ? "left 100ms linear" : "none",
            }}
          />
        ) : null}
      </div>
      {showCounters && (
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 10,
            fontVariantNumeric: "tabular-nums",
            color: theme.textSecondary,
          }}
        >
          <span>{formatTime(elapsedSec)}</span>
          <span>{formatTime(durationSec)}</span>
        </div>
      )}
    </div>
  );
}

function ControlBar({
  theme,
  layout,
  onThemeChange,
  onLayoutChange,
}: {
  theme: ThemeName;
  layout: LayoutName;
  onThemeChange: (t: ThemeName) => void;
  onLayoutChange: (l: LayoutName) => void;
}) {
  return (
    <div
      role="group"
      aria-label="Widget preview controls"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 12,
        padding: "8px 12px 12px 12px",
        flexWrap: "wrap",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span
          style={{
            fontSize: 11,
            textTransform: "uppercase",
            letterSpacing: "0.06em",
            color: "var(--txt-2)",
            fontWeight: 600,
          }}
        >
          Layout
        </span>
        <div
          role="group"
          aria-label="Layout"
          style={{
            display: "inline-flex",
            padding: 2,
            borderRadius: 9999,
            border: "1px solid var(--hairline)",
            background: "var(--bg-surface)",
          }}
        >
          {LAYOUTS.map((l) => {
            const active = l === layout;
            return (
              <button
                key={l}
                type="button"
                onClick={() => onLayoutChange(l)}
                aria-pressed={active}
                style={{
                  minHeight: 36,
                  padding: "7px 13px",
                  fontSize: 12,
                  fontWeight: 600,
                  letterSpacing: "0.02em",
                  color: active ? "#FFFFFF" : "var(--txt-2)",
                  background: active ? "var(--brand-fill)" : "transparent",
                  border: "none",
                  borderRadius: 9999,
                  cursor: "pointer",
                  transition: "background 0.15s ease, color 0.15s ease",
                }}
              >
                {l}
              </button>
            );
          })}
        </div>
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <label
          htmlFor="ww-overlay-theme"
          style={{
            fontSize: 11,
            textTransform: "uppercase",
            letterSpacing: "0.06em",
            color: "var(--txt-2)",
            fontWeight: 600,
          }}
        >
          Theme
        </label>
        <select
          id="ww-overlay-theme"
          value={theme}
          onChange={(e) => onThemeChange(e.target.value as ThemeName)}
          style={{
            minHeight: 36,
            padding: "7px 12px",
            fontSize: 13,
            fontWeight: 500,
            color: "var(--txt-1)",
            background: "var(--bg-surface)",
            border: "1px solid var(--hairline)",
            borderRadius: 8,
            cursor: "pointer",
          }}
        >
          {THEMES.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}

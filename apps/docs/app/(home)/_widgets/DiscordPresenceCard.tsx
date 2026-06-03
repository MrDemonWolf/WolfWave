"use client";

import { AlbumArt } from "./AlbumArt";
import { formatTime } from "./sample-tracks";
import { useCyclingTrack } from "./useCyclingTrack";

/**
 * Discord "Listening to <app>" Rich Presence card recreation.
 *
 * Mirrors the payload built in
 * `apps/native/WolfWave/Services/Discord/DiscordRPCService.swift`
 * `buildActivity(...)`:
 *   - `details`  → bold title
 *   - `state`    → artist
 *   - `large_text` (album) → subtitle italic
 *   - `assets.small_image` "apple_music" → Apple Music corner badge
 *   - `timestamps.start/end` → progress bar + counters
 *   - `buttons[0]` → "Listen on Apple Music"
 *   - `buttons[1]` → "Find on Other Services"
 *
 * No real album art or copyrighted track metadata anywhere. Sample data
 * lives in `./sample-tracks.ts`.
 */
export function DiscordPresenceCard() {
  const { track, elapsedSec, progress, motionEnabled } = useCyclingTrack();

  // Discord brand palette (dark mode).
  const palette = {
    cardBg: "#2B2D31",
    cardBorder: "1px solid rgba(255,255,255,0.06)",
    headerBg: "#1E1F22",
    headerText: "rgba(255,255,255,0.55)",
    headerActive: "#23A559",
    title: "#FFFFFF",
    artist: "#DBDEE1",
    album: "rgba(255,255,255,0.55)",
    progressTrack: "rgba(255,255,255,0.10)",
    progressFill: "#FFFFFF",
    counter: "rgba(255,255,255,0.45)",
    buttonBg: "#4E5058",
    buttonHoverBg: "#6D6F78",
    buttonText: "#FFFFFF",
    appleMusicGradient:
      "linear-gradient(135deg, #FA233B 0%, #FB5C74 100%)",
  };

  return (
    <div
      role="group"
      aria-roledescription="Discord Rich Presence demo"
      aria-label={`Listening to WolfWave: ${track.title} by ${track.artist}`}
      style={{
        width: "100%",
        maxWidth: 360,
        background: palette.cardBg,
        border: palette.cardBorder,
        borderRadius: 8,
        overflow: "hidden",
        fontFamily:
          "'gg sans', 'Inter', var(--ds-font-family-sans), system-ui, sans-serif",
        color: palette.title,
        boxShadow: "0 8px 24px -16px rgba(0,0,0,0.4)",
      }}
    >
      {/* Header strip — mirrors Discord's "Listening to <app>" row. */}
      <div
        style={{
          backgroundColor: palette.headerBg,
          padding: "10px 14px",
          display: "flex",
          alignItems: "center",
          gap: 8,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: "0.04em",
          textTransform: "uppercase",
          color: palette.headerText,
        }}
      >
        <PulsingDot color={palette.headerActive} active={motionEnabled} />
        <span>
          Listening to{" "}
          <span style={{ color: "#F2F3F5" }}>WolfWave</span>
        </span>
      </div>

      {/* Track body */}
      <div style={{ padding: "14px 14px 16px 14px" }}>
        <div style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
          {/* Large image with Apple Music small-image badge */}
          <div
            style={{
              position: "relative",
              transition: "opacity 0.25s ease",
              opacity: 1,
            }}
            key={track.title}
          >
            <AlbumArt
              gradient={track.gradient}
              glyph={track.glyph}
              size={68}
              radius={6}
              ariaLabel={`Generated album art for ${track.title}`}
            />
            {/* small_image: "apple_music" badge */}
            <div
              aria-hidden="true"
              title="Apple Music"
              style={{
                position: "absolute",
                right: -6,
                bottom: -6,
                width: 22,
                height: 22,
                borderRadius: "50%",
                background: palette.appleMusicGradient,
                border: `3px solid ${palette.cardBg}`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                boxShadow: "0 2px 6px rgba(0,0,0,0.4)",
              }}
            >
              <AppleMusicGlyph />
            </div>
          </div>

          {/* Title / artist / album */}
          <div style={{ minWidth: 0, flex: 1, paddingTop: 1 }}>
            <div
              key={`title-${track.title}`}
              style={{
                color: palette.title,
                fontSize: 14,
                fontWeight: 600,
                lineHeight: 1.25,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {track.title}
            </div>
            <div
              style={{
                color: palette.artist,
                fontSize: 12,
                fontWeight: 400,
                marginTop: 2,
                lineHeight: 1.3,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              by {track.artist}
            </div>
            <div
              style={{
                color: palette.album,
                fontSize: 12,
                fontStyle: "italic",
                marginTop: 2,
                lineHeight: 1.3,
                whiteSpace: "nowrap",
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              on {track.album}
            </div>
          </div>
        </div>

        {/* Progress bar */}
        <div style={{ marginTop: 14 }}>
          <div
            role="progressbar"
            aria-label="Track progress"
            aria-valuemin={0}
            aria-valuemax={track.durationSec}
            aria-valuenow={Math.round(elapsedSec)}
            style={{
              position: "relative",
              height: 4,
              background: palette.progressTrack,
              borderRadius: 9999,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                position: "absolute",
                inset: 0,
                width: `${progress * 100}%`,
                background: palette.progressFill,
                borderRadius: 9999,
                transition: motionEnabled
                  ? "width 100ms linear"
                  : "none",
              }}
            />
          </div>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              marginTop: 4,
              fontSize: 11,
              fontVariantNumeric: "tabular-nums",
              color: palette.counter,
            }}
          >
            <span>{formatTime(elapsedSec)}</span>
            <span>{formatTime(track.durationSec)}</span>
          </div>
        </div>

        {/* Buttons */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 8,
            marginTop: 14,
          }}
        >
          <DiscordButton label="Listen on Apple Music" palette={palette} />
          <DiscordButton label="Find on Other Services" palette={palette} />
        </div>
      </div>

      <span className="sr-only">
        Demo card cycles through fictional sample tracks every few seconds.
      </span>
    </div>
  );
}

function PulsingDot({ color, active }: { color: string; active: boolean }) {
  return (
    <span
      aria-hidden="true"
      style={{
        position: "relative",
        display: "inline-block",
        width: 8,
        height: 8,
      }}
    >
      <span
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: "50%",
          background: color,
        }}
      />
      {active && (
        <span
          style={{
            position: "absolute",
            inset: -2,
            borderRadius: "50%",
            background: color,
            opacity: 0.45,
            animation: "ww-discord-dot-pulse 1.6s ease-out infinite",
          }}
        />
      )}
      <style>{`
        @keyframes ww-discord-dot-pulse {
          0%   { transform: scale(0.6); opacity: 0.55; }
          80%  { transform: scale(1.8); opacity: 0;    }
          100% { transform: scale(1.8); opacity: 0;    }
        }
      `}</style>
    </span>
  );
}

function DiscordButton({
  label,
  palette,
}: {
  label: string;
  palette: { buttonBg: string; buttonHoverBg: string; buttonText: string };
}) {
  return (
    <button
      type="button"
      // Demo-only — clicking does nothing. Disabled for screen readers
      // so they don't announce an actionable control we can't honor.
      aria-disabled="true"
      tabIndex={-1}
      onClick={(e) => e.preventDefault()}
      style={{
        display: "block",
        width: "100%",
        padding: "8px 12px",
        fontSize: 14,
        fontWeight: 500,
        color: palette.buttonText,
        background: palette.buttonBg,
        border: "none",
        borderRadius: 3,
        cursor: "default",
        textAlign: "center",
        transition: "background 0.15s ease",
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = palette.buttonHoverBg;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = palette.buttonBg;
      }}
    >
      {label}
    </button>
  );
}

function AppleMusicGlyph() {
  // Simplified eighth-note glyph, white on the red gradient badge.
  return (
    <svg
      width="11"
      height="11"
      viewBox="0 0 24 24"
      aria-hidden="true"
      style={{ display: "block" }}
    >
      <path
        d="M19 4.5c0-.6-.5-1-1.1-.9l-9 1.6c-.5.1-.9.5-.9 1v9.2c-.6-.3-1.3-.4-2-.3-1.5.2-2.6 1.3-2.4 2.5.1 1.2 1.5 2 3 1.8 1.4-.2 2.4-1.2 2.4-2.3V8.7l7-1.2v6.8c-.6-.3-1.3-.4-2-.3-1.5.2-2.6 1.3-2.4 2.5.1 1.2 1.5 2 3 1.8 1.4-.2 2.4-1.2 2.4-2.3V4.5z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

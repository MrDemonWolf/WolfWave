"use client";

import { Twitch, MessageCircle, MonitorPlay } from "lucide-react";
import { AlbumArt } from "./AlbumArt";
import { formatTime } from "./sample-tracks";
import { useCyclingTrack } from "./useCyclingTrack";

/**
 * Hero product visual. A static (no controls) recreation of the WolfWave
 * menu-bar now-playing popover, fanning one Apple Music track out to the
 * three destinations the app drives: Twitch, Discord, OBS. Reuses the
 * shared cycling-track timer so the card feels live without a real feed.
 *
 * Honors prefers-reduced-motion via useCyclingTrack (freezes on track 0).
 */
export function HeroNowPlaying() {
  const { track, elapsedSec, progress, motionEnabled } = useCyclingTrack();

  return (
    <div
      className="ww-glass"
      role="group"
      aria-roledescription="WolfWave now-playing preview"
      style={{ width: "100%", maxWidth: 420, padding: 0, overflow: "hidden" }}
    >
      {/* Menu-bar chrome */}
      <div
        className="flex items-center gap-2"
        style={{
          padding: "12px 16px",
          borderBottom: "1px solid color-mix(in srgb, var(--hairline) 70%, transparent)",
        }}
        aria-hidden="true"
      >
        <span
          className="inline-flex items-center justify-center"
          style={{
            width: 18,
            height: 18,
            borderRadius: 5,
            background: "var(--brand-500)",
            color: "#fff",
            fontSize: 11,
            fontWeight: 700,
          }}
        >
          W
        </span>
        <span className="ww-text-1" style={{ fontSize: 13, fontWeight: 600 }}>
          WolfWave
        </span>
        <span className="ww-text-2" style={{ fontSize: 12, marginLeft: "auto" }}>
          Now Playing
        </span>
      </div>

      {/* Track */}
      <div className="flex items-center gap-4" style={{ padding: 16 }}>
        <AlbumArt
          gradient={track.gradient}
          glyph={track.glyph}
          size={72}
          radius={12}
          ariaLabel={`${track.title} by ${track.artist}`}
        />
        <div style={{ minWidth: 0, flex: 1 }}>
          <div
            className="ww-text-1"
            style={{
              fontSize: 16,
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
            className="ww-text-2"
            style={{
              fontSize: 13,
              marginTop: 3,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.artist}
          </div>
          <div
            className="ww-text-2"
            style={{
              fontSize: 12,
              marginTop: 1,
              opacity: 0.7,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {track.album}
          </div>
        </div>
      </div>

      {/* Progress */}
      <div style={{ padding: "0 16px 14px" }}>
        <div
          role="progressbar"
          aria-label="Track progress"
          aria-valuemin={0}
          aria-valuemax={track.durationSec}
          aria-valuenow={Math.round(elapsedSec)}
          style={{
            position: "relative",
            height: 4,
            background: "color-mix(in srgb, var(--brand-500) 18%, transparent)",
            borderRadius: 9999,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: 0,
              width: `${progress * 100}%`,
              background: "linear-gradient(90deg, var(--brand-600), var(--brand-500))",
              borderRadius: 9999,
              transition: motionEnabled ? "width 100ms linear" : "none",
            }}
          />
        </div>
        <div
          className="ww-text-2"
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 10,
            fontVariantNumeric: "tabular-nums",
            marginTop: 5,
          }}
        >
          <span>{formatTime(elapsedSec)}</span>
          <span>{formatTime(track.durationSec)}</span>
        </div>
      </div>

      {/* Broadcast fan-out */}
      <div
        className="flex items-center gap-2"
        style={{
          padding: "10px 16px",
          borderTop: "1px solid color-mix(in srgb, var(--hairline) 70%, transparent)",
          background: "color-mix(in srgb, var(--bg-surface) 50%, transparent)",
        }}
        aria-label="Broadcasting to Twitch, Discord, and OBS"
      >
        <span
          className="ww-text-2"
          style={{ fontSize: 10, textTransform: "uppercase", letterSpacing: "0.06em", fontWeight: 600 }}
        >
          Live on
        </span>
        {[
          { Icon: Twitch, label: "Twitch" },
          { Icon: MessageCircle, label: "Discord" },
          { Icon: MonitorPlay, label: "OBS" },
        ].map(({ Icon, label }) => (
          <span
            key={label}
            className="inline-flex items-center gap-1.5"
            style={{
              fontSize: 11,
              fontWeight: 600,
              padding: "3px 8px",
              borderRadius: 9999,
              color: "var(--brand-500)",
              background: "color-mix(in srgb, var(--brand-500) 12%, transparent)",
            }}
          >
            <Icon style={{ width: 12, height: 12 }} aria-hidden="true" />
            {label}
          </span>
        ))}
        <span
          aria-hidden="true"
          style={{
            width: 7,
            height: 7,
            borderRadius: 9999,
            background: "#34C759",
            marginLeft: "auto",
            boxShadow: "0 0 0 3px color-mix(in srgb, #34C759 25%, transparent)",
          }}
        />
      </div>
    </div>
  );
}

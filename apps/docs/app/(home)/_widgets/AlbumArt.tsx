"use client";

import type { SampleGlyph } from "./sample-tracks";

interface AlbumArtProps {
  gradient: string;
  glyph: SampleGlyph;
  size: number;
  /** Optional rounded-corner radius in px. Defaults to 14% of size. */
  radius?: number;
  /** Optional aria-label for screen readers. */
  ariaLabel?: string;
}

/**
 * Stand-in for an album cover. CSS gradient background with a centered
 * generic glyph (vinyl, cassette, wave, broadcast tower). Never displays
 * real artwork, keeping the marketing site clear of third-party imagery.
 */
export function AlbumArt({
  gradient,
  glyph,
  size,
  radius,
  ariaLabel,
}: AlbumArtProps) {
  const r = radius ?? size * 0.14;
  return (
    <div
      role={ariaLabel ? "img" : "presentation"}
      aria-label={ariaLabel}
      style={{
        width: size,
        height: size,
        borderRadius: r,
        background: gradient,
        position: "relative",
        flexShrink: 0,
        overflow: "hidden",
        boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
      }}
    >
      {/* Subtle vignette for depth */}
      <div
        aria-hidden="true"
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(circle at 70% 30%, rgba(255,255,255,0.22), transparent 55%)",
          pointerEvents: "none",
        }}
      />
      <Glyph glyph={glyph} size={size} />
    </div>
  );
}

function Glyph({ glyph, size }: { glyph: SampleGlyph; size: number }) {
  const inner = size * 0.55;
  const stroke = Math.max(1.25, size * 0.018);
  const common = {
    width: inner,
    height: inner,
    viewBox: "0 0 100 100",
    fill: "none",
    stroke: "rgba(255,255,255,0.85)",
    strokeWidth: stroke,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    style: {
      position: "absolute" as const,
      top: "50%",
      left: "50%",
      transform: "translate(-50%, -50%)",
      filter: "drop-shadow(0 1px 2px rgba(0,0,0,0.35))",
    },
  };

  switch (glyph) {
    case "vinyl":
      return (
        <svg {...common} aria-hidden="true">
          <circle cx="50" cy="50" r="40" />
          <circle cx="50" cy="50" r="26" />
          <circle cx="50" cy="50" r="12" />
          <circle cx="50" cy="50" r="4" fill="rgba(255,255,255,0.85)" stroke="none" />
        </svg>
      );
    case "cassette":
      return (
        <svg {...common} aria-hidden="true">
          <rect x="12" y="22" width="76" height="56" rx="6" />
          <circle cx="34" cy="50" r="10" />
          <circle cx="66" cy="50" r="10" />
          <line x1="20" y1="70" x2="80" y2="70" />
        </svg>
      );
    case "wave":
      return (
        <svg {...common} aria-hidden="true">
          <path d="M10 50 Q 25 20, 40 50 T 70 50 T 100 50" />
          <path
            d="M10 60 Q 25 30, 40 60 T 70 60 T 100 60"
            opacity="0.6"
          />
          <path
            d="M10 70 Q 25 40, 40 70 T 70 70 T 100 70"
            opacity="0.35"
          />
        </svg>
      );
    case "broadcast":
      return (
        <svg {...common} aria-hidden="true">
          <circle cx="50" cy="55" r="6" fill="rgba(255,255,255,0.85)" stroke="none" />
          <path d="M30 65 Q 50 35, 70 65" />
          <path d="M20 75 Q 50 25, 80 75" opacity="0.7" />
          <line x1="50" y1="55" x2="42" y2="85" />
          <line x1="50" y1="55" x2="58" y2="85" />
        </svg>
      );
  }
}

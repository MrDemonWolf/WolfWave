/**
 * Sample tracks for the live widget demos on the landing page.
 *
 * IMPORTANT — all titles and artist names are invented. No real
 * recording-artist names, song titles, or album art appear on the
 * marketing site. Album art is rendered as a CSS gradient with a
 * generic SVG glyph so we never display third-party copyrighted
 * imagery.
 *
 * Field shape mirrors the WebSocket `now_playing.data` payload from
 * `apps/native/WolfWave/Services/WebSocket/WebSocketServerService.swift`
 * so a future swap to a live feed would be a one-line change.
 */

export type SampleGlyph = "vinyl" | "cassette" | "wave" | "broadcast";

export interface SampleTrack {
  /** Discord `details` / widget `track` */
  title: string;
  /** Discord `state` / widget `artist` */
  artist: string;
  /** Discord `assets.large_text` / widget `album` */
  album: string;
  /** Real track duration in seconds (matches WebSocket payload). */
  durationSec: number;
  /** CSS background for the fake album art square. */
  gradient: string;
  /** Identifier for the centered SVG glyph layered over the gradient. */
  glyph: SampleGlyph;
}

export const SAMPLE_TRACKS: SampleTrack[] = [
  {
    title: "Midnight Routine",
    artist: "Local Maxima",
    album: "Soft Landings",
    durationSec: 218,
    gradient: "linear-gradient(135deg, #5865F2 0%, #0A84FF 100%)",
    glyph: "vinyl",
  },
  {
    title: "Static Bloom",
    artist: "Carrier Wave",
    album: "Daylight Saving",
    durationSec: 247,
    gradient: "linear-gradient(135deg, #34C759 0%, #5AC8FA 100%)",
    glyph: "wave",
  },
  {
    title: "Paper Lanterns",
    artist: "Hours & Halves",
    album: "Folded Routes",
    durationSec: 191,
    gradient: "linear-gradient(135deg, #FF9F0A 0%, #FF453A 100%)",
    glyph: "cassette",
  },
  {
    title: "Tide Maps",
    artist: "Quiet Modem",
    album: "Northbound",
    durationSec: 263,
    gradient: "linear-gradient(135deg, #BF5AF2 0%, #FF375F 100%)",
    glyph: "broadcast",
  },
];

/** Format seconds as `m:ss`. */
export function formatTime(totalSec: number): string {
  const safe = Math.max(0, Math.floor(totalSec));
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

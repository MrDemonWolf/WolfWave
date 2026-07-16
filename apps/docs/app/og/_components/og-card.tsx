import type { ReactElement, ReactNode } from "react";
import { SAMPLE_TRACKS } from "../../(home)/_widgets/sample-tracks";

// ── Palette (Apple-dark, brand blue) ──────────────────────────
const BG = "#000000";
const BG_RAISED = "#0E0E11";
const SURFACE = "#1C1C1E";
const SURFACE_HI = "#242427";
const HAIRLINE = "#2C2C2E";
const BRAND = "#0A84FF";
const BRAND_HI = "#409CFF";
const TXT_1 = "#F5F5F7";
const TXT_2 = "#A1A1A6";

// Destination brand colors for the now-playing tile.
const TWITCH = "#9146FF";
const DISCORD = "#5865F2";

/** Audio-waveform glyph. Cues the music app. */
function WaveGlyph({ size = 30, color = BRAND_HI, bars = [0.35, 0.7, 1.0, 0.55, 0.85, 0.4] }: { size?: number; color?: string; bars?: number[] }): ReactElement {
  const barW = size / (bars.length * 2 - 1);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: barW, height: size }}>
      {bars.map((h, i) => (
        <div
          key={i}
          style={{
            display: "flex",
            width: barW,
            height: Math.max(size * h, barW),
            borderRadius: barW,
            background: color,
          }}
        />
      ))}
    </div>
  );
}

/** Wordmark. Wave glyph plus the wolfwave text, used top-left on every card. */
function Wordmark(): ReactElement {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <WaveGlyph size={30} color={BRAND_HI} />
      <div
        style={{
          display: "flex",
          fontFamily: "Inter",
          fontSize: 34,
          fontWeight: 700,
          color: TXT_1,
          letterSpacing: -1,
        }}
      >
        wolfwave
      </div>
    </div>
  );
}

/**
 * Shared card chrome: background, glows, dot grid, inset frame, and a
 * header row (wordmark left, mono tag right). Children render in the body.
 */
function Frame({ tag, children }: { tag: string; children: ReactNode }): ReactElement {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: BG,
        position: "relative",
        fontFamily: "Inter",
      }}
    >
      {/* Vertical base gradient */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `linear-gradient(160deg, ${BG_RAISED} 0%, ${BG} 55%)`,
          display: "flex",
        }}
      />
      {/* One soft brand glow, top-left. Single light source reads cleaner
          than competing glows plus a texture. */}
      <div
        style={{
          position: "absolute",
          top: -360,
          left: -300,
          width: 1000,
          height: 1000,
          background: `radial-gradient(circle, ${BRAND}40 0%, ${BRAND}00 58%)`,
          display: "flex",
        }}
      />
      {/* Inset hairline frame */}
      <div style={{ position: "absolute", inset: 22, border: `1px solid ${HAIRLINE}`, borderRadius: 30, display: "flex" }} />

      {/* Header row */}
      <div
        style={{
          position: "relative",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "50px 64px 0",
        }}
      >
        <Wordmark />
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            fontFamily: "JetBrains Mono",
            fontSize: 16,
            color: TXT_2,
            letterSpacing: 0.4,
          }}
        >
          <div style={{ display: "flex", width: 7, height: 7, borderRadius: 999, background: BRAND_HI, boxShadow: `0 0 12px ${BRAND_HI}` }} />
          <span style={{ display: "flex" }}>{tag}</span>
        </div>
      </div>

      {/* Body */}
      <div style={{ position: "relative", display: "flex", flex: 1, padding: "34px 64px 44px" }}>{children}</div>
    </div>
  );
}

// ── Eyebrow pill ──────────────────────────────────────────────
function Eyebrow({ text }: { text: string }): ReactElement {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        alignSelf: "flex-start",
        gap: 12,
        padding: "9px 20px 9px 15px",
        borderRadius: 999,
        background: `${BRAND}24`,
        border: `1px solid ${BRAND}55`,
        color: BRAND_HI,
        fontSize: 21,
        fontWeight: 500,
        letterSpacing: -0.2,
      }}
    >
      <div style={{ display: "flex", width: 10, height: 10, borderRadius: 999, background: BRAND_HI, boxShadow: `0 0 14px ${BRAND_HI}` }} />
      <span style={{ display: "flex" }}>{text}</span>
    </div>
  );
}

// ── Now-playing tile (right column) ───────────────────────────
/** Destination marker. Borderless dot + label so the three sit on one
    clean row instead of wrapping into bordered pills. */
function DestChip({ color, label }: { color: string; label: string }): ReactElement {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ display: "flex", width: 10, height: 10, borderRadius: 999, background: color, boxShadow: `0 0 12px ${color}` }} />
      <span style={{ display: "flex", fontSize: 18, fontWeight: 600, color: TXT_1 }}>{label}</span>
    </div>
  );
}

function NowPlayingTile(): ReactElement {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        width: 372,
        gap: 24,
        padding: 28,
        borderRadius: 28,
        background: SURFACE,
        border: `1px solid ${HAIRLINE}`,
        boxShadow: "0 30px 80px -30px rgba(0,0,0,0.8)",
      }}
    >
      {/* Track header */}
      <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
        {/* Album art mock */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            width: 92,
            height: 92,
            borderRadius: 20,
            background: `linear-gradient(135deg, ${BRAND} 0%, ${TWITCH} 100%)`,
            boxShadow: `0 14px 32px -10px ${BRAND}88`,
          }}
        >
          <WaveGlyph size={42} color="#FFFFFF" bars={[0.4, 0.85, 0.6, 1.0, 0.5]} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", flex: 1 }}>
          <div style={{ display: "flex", fontFamily: "JetBrains Mono", fontSize: 14, color: BRAND_HI, letterSpacing: 0.6 }}>
            NOW PLAYING
          </div>
          <div style={{ display: "flex", marginTop: 7, fontSize: 27, fontWeight: 700, color: TXT_1, letterSpacing: -0.6 }}>
            {SAMPLE_TRACKS[0].title}
          </div>
          <div style={{ display: "flex", marginTop: 3, fontSize: 19, color: TXT_2 }}>{SAMPLE_TRACKS[0].artist}</div>
        </div>
      </div>

      {/* Progress */}
      <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
        <div style={{ display: "flex", height: 6, borderRadius: 999, background: SURFACE_HI }}>
          <div style={{ display: "flex", width: "44%", height: 6, borderRadius: 999, background: BRAND_HI }} />
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontFamily: "JetBrains Mono", fontSize: 14, color: TXT_2 }}>
          <span style={{ display: "flex" }}>1:34</span>
          <span style={{ display: "flex" }}>3:32</span>
        </div>
      </div>

      {/* Divider */}
      <div style={{ display: "flex", height: 1, background: HAIRLINE }} />

      {/* Same track, three destinations, on one clean row. */}
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <div style={{ display: "flex", fontFamily: "JetBrains Mono", fontSize: 13, color: TXT_2, letterSpacing: 0.5 }}>
          LIVE ON
        </div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <DestChip color={TWITCH} label="Twitch" />
          <DestChip color={DISCORD} label="Discord" />
          <DestChip color={BRAND_HI} label="OBS" />
        </div>
      </div>
    </div>
  );
}

// ── Title with accent word ────────────────────────────────────
function splitAccent(title: string, accentWord?: string): [string, string, string] {
  if (!accentWord) return [title, "", ""];
  const idx = title.toLowerCase().indexOf(accentWord.toLowerCase());
  if (idx === -1) return [title, "", ""];
  return [title.slice(0, idx), title.slice(idx, idx + accentWord.length), title.slice(idx + accentWord.length)];
}

export interface OgCardProps {
  title: string;
  description?: string;
  eyebrow?: string;
  chips?: string[];
  accentWord?: string;
}

/** The standard 1200x630 social card: accent-split headline, capped description, chip row. */
export function OgCard({ title, description, eyebrow, chips, accentWord }: OgCardProps): ReactElement {
  const [before, accent, after] = splitAccent(title, accentWord);
  // Cap the description so a long docs frontmatter line can't push the chips
  // off the bottom of the 1200x630 frame.
  const desc =
    description && description.length > 120
      ? `${description
          .slice(0, 116)
          .replace(/\s+\S*$/, "")
          .replace(/[\s.,;:!?]+$/, "")}…`
      : description;

  return (
    <Frame tag="macOS · native · open source">
      <div style={{ display: "flex", width: "100%", justifyContent: "space-between", alignItems: "flex-start", gap: 56 }}>
        {/* Left column. Message. Top-aligned so a tall block never overflows
            up into the header row (which collides with the wordmark). */}
        <div style={{ display: "flex", flexDirection: "column", flex: 1, justifyContent: "flex-start" }}>
          {eyebrow ? <Eyebrow text={eyebrow} /> : null}

          {/* Headline. Rendered one word per flex item so Satori wraps it on
              word boundaries instead of clipping a single long flex child. */}
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              columnGap: 18,
              rowGap: 4,
              marginTop: eyebrow ? 26 : 0,
              fontFamily: "Inter",
              fontSize: 54,
              lineHeight: 1.1,
              fontWeight: 700,
              letterSpacing: -1.8,
              maxWidth: 540,
            }}
          >
            {[
              { text: before, color: TXT_1 },
              { text: accent, color: BRAND_HI },
              { text: after, color: TXT_1 },
            ]
              .filter((seg) => seg.text.trim().length > 0)
              .flatMap((seg, si) =>
                seg.text
                  .trim()
                  .split(/\s+/)
                  .map((word, wi) => (
                    <span key={`${si}-${wi}`} style={{ display: "flex", color: seg.color }}>
                      {word}
                    </span>
                  )),
              )}
          </div>

          {desc ? (
            <div style={{ display: "flex", marginTop: 22, fontSize: 24, lineHeight: 1.4, color: TXT_2, letterSpacing: -0.3, maxWidth: 560 }}>
              {desc}
            </div>
          ) : null}

          {chips && chips.length > 0 ? (
            <div style={{ display: "flex", gap: 9, flexWrap: "wrap", marginTop: 24, maxWidth: 600 }}>
              {chips.map((c) => (
                <div
                  key={c}
                  style={{
                    display: "flex",
                    padding: "7px 16px",
                    borderRadius: 999,
                    background: SURFACE,
                    border: `1px solid ${HAIRLINE}`,
                    color: TXT_1,
                    fontSize: 18,
                    fontWeight: 500,
                    letterSpacing: -0.2,
                  }}
                >
                  {c}
                </div>
              ))}
            </div>
          ) : null}
        </div>

        {/* Right column. Now-playing proof */}
        <NowPlayingTile />
      </div>
    </Frame>
  );
}

export interface ChangelogOgCardProps {
  version: string;
  date: string;
  highlights: string[];
}

/** The changelog-specific social card: large version number, date, and top-3 highlights. */
export function ChangelogOgCard({ version, date, highlights }: ChangelogOgCardProps): ReactElement {
  return (
    <Frame tag="release notes">
      <div style={{ display: "flex", flexDirection: "column", flex: 1, justifyContent: "center" }}>
        <Eyebrow text={`Changelog · ${date}`} />

        <div style={{ display: "flex", marginTop: 26, fontFamily: "Inter", fontSize: 132, lineHeight: 1, color: TXT_1, fontWeight: 700, letterSpacing: -3.2 }}>
          <span style={{ display: "flex" }}>v</span>
          <span style={{ display: "flex", color: BRAND_HI, fontWeight: 700 }}>{version}</span>
        </div>

        <div style={{ display: "flex", marginTop: 14, fontSize: 29, color: TXT_2, letterSpacing: -0.3 }}>
          What&apos;s new in WolfWave
        </div>

        <div style={{ display: "flex", flexDirection: "column", marginTop: 28, gap: 13 }}>
          {highlights.slice(0, 3).map((h, i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 26, color: TXT_1, fontWeight: 500, letterSpacing: -0.3 }}>
              <div style={{ display: "flex", width: 4, height: 22, borderRadius: 2, background: BRAND_HI }} />
              <span style={{ display: "flex" }}>{h}</span>
            </div>
          ))}
        </div>
      </div>
    </Frame>
  );
}

export const OG_SIZE = { width: 1200, height: 630 } as const;
export const OG_CONTENT_TYPE = "image/png" as const;

async function loadFont(family: string, weights: number[], italic = false): Promise<{ name: string; data: ArrayBuffer; weight: number; style: "normal" | "italic" }[]> {
  const results: { name: string; data: ArrayBuffer; weight: number; style: "normal" | "italic" }[] = [];
  for (const weight of weights) {
    const ital = italic ? "ital," : "";
    const italVal = italic ? "1," : "";
    const url = `https://fonts.googleapis.com/css2?family=${family.replace(/ /g, "+")}:${ital}wght@${italVal}${weight}&display=swap`;
    const css = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } }).then((r) => r.text());
    const match = css.match(/src:\s*url\(([^)]+)\)\s*format\('(?:truetype|woff2?)'\)/);
    if (!match) continue;
    const fontData = await fetch(match[1]).then((r) => r.arrayBuffer());
    results.push({ name: family, data: fontData, weight, style: italic ? "italic" : "normal" });
  }
  return results;
}

/** Fetches the Inter + JetBrains Mono font buffers Satori needs to render the OG cards. */
export async function loadOgFonts() {
  const [inter, mono] = await Promise.all([
    loadFont("Inter", [400, 500, 700]),
    loadFont("JetBrains Mono", [400]),
  ]);
  return [...inter, ...mono];
}

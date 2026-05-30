import type { ReactElement, ReactNode } from "react";

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

/** Inline SVG dot grid. Subtle Apple-keynote texture, rendered via data URI. */
const DOT_GRID = `url("data:image/svg+xml;utf8,${encodeURIComponent(
  `<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'><circle cx='1' cy='1' r='1' fill='%23ffffff' fill-opacity='0.04'/></svg>`,
)}")`;

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
      {/* Dot-grid texture */}
      <div style={{ position: "absolute", inset: 0, backgroundImage: DOT_GRID, backgroundRepeat: "repeat", display: "flex" }} />
      {/* Brand glow, top-left */}
      <div
        style={{
          position: "absolute",
          top: -320,
          left: -280,
          width: 920,
          height: 920,
          background: `radial-gradient(circle, ${BRAND}5C 0%, ${BRAND}00 55%)`,
          display: "flex",
        }}
      />
      {/* Highlight glow, bottom-right */}
      <div
        style={{
          position: "absolute",
          bottom: -360,
          right: -220,
          width: 860,
          height: 860,
          background: `radial-gradient(circle, ${BRAND_HI}33 0%, ${BRAND_HI}00 58%)`,
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
          padding: "56px 64px 0",
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
      <div style={{ position: "relative", display: "flex", flex: 1, padding: "40px 64px 56px" }}>{children}</div>
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
function PlatformRow({ color, label, value }: { color: string; label: string; value: string }): ReactElement {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <div style={{ display: "flex", width: 11, height: 11, borderRadius: 999, background: color, boxShadow: `0 0 12px ${color}AA` }} />
      <div style={{ display: "flex", flex: 1, fontSize: 19, color: TXT_2 }}>
        <span style={{ display: "flex", color: TXT_1, fontWeight: 600 }}>{label}</span>
        <span style={{ display: "flex", marginLeft: 8 }}>{value}</span>
      </div>
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
        gap: 22,
        padding: 26,
        borderRadius: 26,
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
            width: 86,
            height: 86,
            borderRadius: 18,
            background: `linear-gradient(135deg, ${BRAND} 0%, ${TWITCH} 100%)`,
            boxShadow: `0 12px 30px -10px ${BRAND}88`,
          }}
        >
          <WaveGlyph size={40} color="#FFFFFF" bars={[0.4, 0.85, 0.6, 1.0, 0.5]} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", flex: 1 }}>
          <div style={{ display: "flex", fontFamily: "JetBrains Mono", fontSize: 14, color: BRAND_HI, letterSpacing: 0.6 }}>
            NOW PLAYING
          </div>
          <div style={{ display: "flex", marginTop: 6, fontSize: 26, fontWeight: 700, color: TXT_1, letterSpacing: -0.6 }}>
            Midnight Drive
          </div>
          <div style={{ display: "flex", marginTop: 2, fontSize: 19, color: TXT_2 }}>Neon Coast</div>
        </div>
      </div>

      {/* Progress */}
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
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

      {/* Same track, three destinations */}
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <PlatformRow color={TWITCH} label="Twitch" value="!song in chat" />
        <PlatformRow color={DISCORD} label="Discord" value="Rich Presence" />
        <PlatformRow color={BRAND_HI} label="OBS" value="overlay live" />
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

export function OgCard({ title, description, eyebrow, chips, accentWord }: OgCardProps): ReactElement {
  const [before, accent, after] = splitAccent(title, accentWord);

  return (
    <Frame tag="macOS · native · open source">
      <div style={{ display: "flex", width: "100%", justifyContent: "space-between", alignItems: "center", gap: 56 }}>
        {/* Left column. Message */}
        <div style={{ display: "flex", flexDirection: "column", flex: 1, justifyContent: "center" }}>
          {eyebrow ? <Eyebrow text={eyebrow} /> : null}

          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              marginTop: eyebrow ? 30 : 0,
              fontFamily: "Inter",
              fontSize: 72,
              lineHeight: 1.04,
              color: TXT_1,
              fontWeight: 700,
              letterSpacing: -2,
              maxWidth: 620,
            }}
          >
            <span style={{ display: "flex" }}>{before}</span>
            {accent ? <span style={{ display: "flex", color: BRAND_HI, fontWeight: 700 }}>{accent}</span> : null}
            {after ? <span style={{ display: "flex" }}>{after}</span> : null}
          </div>

          {description ? (
            <div style={{ display: "flex", marginTop: 26, fontSize: 27, lineHeight: 1.35, color: TXT_2, letterSpacing: -0.3, maxWidth: 600 }}>
              {description}
            </div>
          ) : null}

          {chips && chips.length > 0 ? (
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 34, maxWidth: 620 }}>
              {chips.map((c) => (
                <div
                  key={c}
                  style={{
                    display: "flex",
                    padding: "8px 18px",
                    borderRadius: 999,
                    background: SURFACE,
                    border: `1px solid ${HAIRLINE}`,
                    color: TXT_1,
                    fontSize: 20,
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

export async function loadOgFonts() {
  const [inter, mono] = await Promise.all([
    loadFont("Inter", [400, 500, 700]),
    loadFont("JetBrains Mono", [400]),
  ]);
  return [...inter, ...mono];
}

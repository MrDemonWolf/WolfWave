import type { ReactElement } from "react";

const BG = "#000000";
const SURFACE = "#1C1C1E";
const HAIRLINE = "#2C2C2E";
const BRAND = "#0A84FF";
const BRAND_HI = "#409CFF";
const TXT_1 = "#F5F5F7";
const TXT_2 = "#A1A1A6";

export interface OgCardProps {
  title: string;
  description?: string;
  eyebrow?: string;
  chips?: string[];
  accentWord?: string;
}

function splitAccent(title: string, accentWord?: string): [string, string, string] {
  if (!accentWord) return [title, "", ""];
  const idx = title.toLowerCase().indexOf(accentWord.toLowerCase());
  if (idx === -1) return [title, "", ""];
  return [title.slice(0, idx), title.slice(idx, idx + accentWord.length), title.slice(idx + accentWord.length)];
}

export function OgCard({ title, description, eyebrow, chips, accentWord }: OgCardProps): ReactElement {
  const [before, accent, after] = splitAccent(title, accentWord);

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: BG,
        position: "relative",
        fontFamily: "Instrument Sans",
      }}
    >
      {/* Blue glow top-left */}
      <div
        style={{
          position: "absolute",
          top: -260,
          left: -260,
          width: 900,
          height: 900,
          background: `radial-gradient(circle, ${BRAND}55 0%, ${BRAND}00 60%)`,
          display: "flex",
        }}
      />
      {/* Subtle glow bottom-right */}
      <div
        style={{
          position: "absolute",
          bottom: -300,
          right: -200,
          width: 700,
          height: 700,
          background: `radial-gradient(circle, ${BRAND_HI}33 0%, ${BRAND_HI}00 60%)`,
          display: "flex",
        }}
      />

      {/* Hairline frame */}
      <div
        style={{
          position: "absolute",
          inset: 24,
          border: `1px solid ${HAIRLINE}`,
          borderRadius: 28,
          display: "flex",
        }}
      />

      {/* Content */}
      <div
        style={{
          position: "relative",
          display: "flex",
          flexDirection: "column",
          padding: "88px 96px",
          flex: 1,
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          {eyebrow ? (
            <div
              style={{
                display: "flex",
                alignSelf: "flex-start",
                padding: "10px 20px",
                borderRadius: 999,
                background: `${BRAND}24`,
                border: `1px solid ${BRAND}55`,
                color: BRAND_HI,
                fontSize: 22,
                fontWeight: 500,
                letterSpacing: 0.3,
                marginBottom: 36,
              }}
            >
              {eyebrow}
            </div>
          ) : null}

          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              fontFamily: "Unbounded",
              fontSize: 88,
              lineHeight: 1.05,
              color: TXT_1,
              fontWeight: 600,
              letterSpacing: -1.5,
              maxWidth: 1000,
            }}
          >
            <span style={{ display: "flex" }}>{before}</span>
            {accent ? (
              <span
                style={{
                  display: "flex",
                  fontFamily: "Instrument Serif",
                  fontStyle: "italic",
                  fontWeight: 400,
                  backgroundImage: `linear-gradient(90deg, ${BRAND} 0%, ${BRAND_HI} 100%)`,
                  backgroundClip: "text",
                  color: "transparent",
                  marginLeft: before.endsWith(" ") || before.length === 0 ? 0 : 16,
                  marginRight: after.startsWith(" ") || after.length === 0 ? 0 : 16,
                }}
              >
                {accent}
              </span>
            ) : null}
            {after ? <span style={{ display: "flex" }}>{after}</span> : null}
          </div>

          {description ? (
            <div
              style={{
                display: "flex",
                marginTop: 32,
                fontSize: 32,
                lineHeight: 1.35,
                color: TXT_2,
                maxWidth: 920,
              }}
            >
              {description}
            </div>
          ) : null}
        </div>

        <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
          <div style={{ display: "flex", gap: 14, flexWrap: "wrap", maxWidth: 660 }}>
            {(chips ?? []).map((c) => (
              <div
                key={c}
                style={{
                  display: "flex",
                  padding: "10px 20px",
                  borderRadius: 999,
                  background: SURFACE,
                  border: `1px solid ${HAIRLINE}`,
                  color: TXT_1,
                  fontSize: 22,
                  fontWeight: 500,
                }}
              >
                {c}
              </div>
            ))}
          </div>

          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
            <div
              style={{
                display: "flex",
                fontFamily: "Unbounded",
                fontSize: 36,
                fontWeight: 600,
                color: TXT_1,
                letterSpacing: -0.5,
              }}
            >
              wolfwave
            </div>
            <div
              style={{
                display: "flex",
                marginTop: 6,
                fontFamily: "JetBrains Mono",
                fontSize: 18,
                color: TXT_2,
              }}
            >
              mrdemonwolf.github.io/wolfwave
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export interface ChangelogOgCardProps {
  version: string;
  date: string;
  highlights: string[];
}

export function ChangelogOgCard({ version, date, highlights }: ChangelogOgCardProps): ReactElement {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: BG,
        position: "relative",
        fontFamily: "Instrument Sans",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: -260,
          left: -260,
          width: 900,
          height: 900,
          background: `radial-gradient(circle, ${BRAND}55 0%, ${BRAND}00 60%)`,
          display: "flex",
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: -300,
          right: -200,
          width: 700,
          height: 700,
          background: `radial-gradient(circle, ${BRAND_HI}33 0%, ${BRAND_HI}00 60%)`,
          display: "flex",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 24,
          border: `1px solid ${HAIRLINE}`,
          borderRadius: 28,
          display: "flex",
        }}
      />
      <div
        style={{
          position: "relative",
          display: "flex",
          flexDirection: "column",
          padding: "72px 96px",
          flex: 1,
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div
            style={{
              display: "flex",
              alignSelf: "flex-start",
              padding: "10px 20px",
              borderRadius: 999,
              background: `${BRAND}24`,
              border: `1px solid ${BRAND}55`,
              color: BRAND_HI,
              fontSize: 22,
              fontWeight: 500,
              letterSpacing: 0.3,
              marginBottom: 28,
            }}
          >
            Changelog · {date}
          </div>
          <div
            style={{
              display: "flex",
              fontFamily: "Unbounded",
              fontSize: 130,
              lineHeight: 1,
              color: TXT_1,
              fontWeight: 600,
              letterSpacing: -3,
            }}
          >
            <span style={{ display: "flex" }}>v</span>
            <span
              style={{
                display: "flex",
                fontFamily: "Instrument Serif",
                fontStyle: "italic",
                fontWeight: 400,
                backgroundImage: `linear-gradient(90deg, ${BRAND} 0%, ${BRAND_HI} 100%)`,
                backgroundClip: "text",
                color: "transparent",
              }}
            >
              {version}
            </span>
          </div>
          <div
            style={{
              display: "flex",
              marginTop: 16,
              fontSize: 30,
              color: TXT_2,
              letterSpacing: 0.2,
            }}
          >
            What&apos;s new in WolfWave
          </div>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 28,
              gap: 12,
            }}
          >
            {highlights.slice(0, 3).map((h, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 14,
                  fontSize: 26,
                  color: TXT_1,
                  fontWeight: 500,
                }}
              >
                <span
                  style={{
                    display: "flex",
                    width: 8,
                    height: 8,
                    borderRadius: 999,
                    background: BRAND_HI,
                  }}
                />
                <span style={{ display: "flex" }}>{h}</span>
              </div>
            ))}
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "flex-end" }}>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}>
            <div
              style={{
                display: "flex",
                fontFamily: "Unbounded",
                fontSize: 36,
                fontWeight: 600,
                color: TXT_1,
                letterSpacing: -0.5,
              }}
            >
              wolfwave
            </div>
            <div
              style={{
                display: "flex",
                marginTop: 6,
                fontFamily: "JetBrains Mono",
                fontSize: 18,
                color: TXT_2,
              }}
            >
              mrdemonwolf.github.io/wolfwave
            </div>
          </div>
        </div>
      </div>
    </div>
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
  const [unbounded, instrument, instrumentItalic, mono] = await Promise.all([
    loadFont("Unbounded", [600]),
    loadFont("Instrument Sans", [400, 500]),
    loadFont("Instrument Serif", [400], true),
    loadFont("JetBrains Mono", [400]),
  ]);
  return [...unbounded, ...instrument, ...instrumentItalic, ...mono];
}

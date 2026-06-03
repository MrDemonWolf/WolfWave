import { Check, Minus, X as XIcon } from "lucide-react";

/**
 * Responsive WolfWave-vs-the-rest comparison.
 *
 * Desktop (>= md): a real table.
 * Mobile / tablet (< md): the table would force a horizontal scroll, which
 * reads badly on a phone, so the same data renders as one stacked card per
 * feature with the three columns as labeled rows. WolfWave's row is
 * emphasized so the takeaway survives the smaller layout.
 */

type CellState = "yes" | "no" | "partial";

const COLUMNS = ["WolfWave", "Browser source widgets", "Spotify-only bots"] as const;

interface Row {
  feature: string;
  ww: CellState;
  browser: CellState;
  spotify: CellState;
}

const ROWS: Row[] = [
  { feature: "Apple Music support", ww: "yes", browser: "partial", spotify: "no" },
  { feature: "Native macOS app", ww: "yes", browser: "no", spotify: "no" },
  { feature: "Free, no paywall", ww: "yes", browser: "partial", spotify: "partial" },
  { feature: "Chat song requests", ww: "yes", browser: "no", spotify: "yes" },
  { feature: "Stream overlay included", ww: "yes", browser: "yes", spotify: "no" },
  { feature: "Discord Rich Presence", ww: "yes", browser: "no", spotify: "no" },
  { feature: "Open source", ww: "yes", browser: "partial", spotify: "no" },
];

function stateLabel(state: CellState): string {
  return state === "yes" ? "Yes" : state === "no" ? "No" : "Partial";
}

function CompareIcon({ state }: { state: CellState }) {
  const tone =
    state === "yes"
      ? { bg: "var(--brand-50)", color: "var(--brand-500)" }
      : { bg: "var(--bg-surface)", color: "var(--txt-2)" };
  const Icon = state === "yes" ? Check : state === "partial" ? Minus : XIcon;
  return (
    <span
      className="inline-flex items-center justify-center w-7 h-7 rounded-full"
      style={{ backgroundColor: tone.bg, color: tone.color }}
      aria-label={stateLabel(state)}
    >
      <Icon className="w-3.5 h-3.5" aria-hidden="true" />
    </span>
  );
}

export function ComparisonTable() {
  return (
    <>
      {/* Desktop / large tablet: real table */}
      <div className="mt-12 hidden md:block">
        <div
          className="ww-card ww-bg-base"
          style={{ border: "1px solid var(--hairline)" }}
        >
          <table className="w-full text-sm">
            <thead>
              <tr style={{ borderBottom: "1px solid var(--hairline)" }}>
                <th
                  className="text-left py-4 pr-4 ww-text-2 font-medium"
                  scope="col"
                >
                  Feature
                </th>
                <th
                  className="text-center py-4 px-3 ww-text-brand font-semibold"
                  scope="col"
                >
                  WolfWave
                </th>
                <th
                  className="text-center py-4 px-3 ww-text-2 font-medium"
                  scope="col"
                >
                  Browser source widgets
                </th>
                <th
                  className="text-center py-4 pl-3 ww-text-2 font-medium"
                  scope="col"
                >
                  Spotify-only bots
                </th>
              </tr>
            </thead>
            <tbody>
              {ROWS.map((row, i) => (
                <tr
                  key={row.feature}
                  style={
                    i < ROWS.length - 1
                      ? { borderBottom: "1px solid var(--hairline)" }
                      : undefined
                  }
                >
                  <td className="py-4 pr-4 ww-text-1">{row.feature}</td>
                  <td className="py-4 px-3">
                    <div className="flex justify-center">
                      <CompareIcon state={row.ww} />
                    </div>
                  </td>
                  <td className="py-4 px-3">
                    <div className="flex justify-center">
                      <CompareIcon state={row.browser} />
                    </div>
                  </td>
                  <td className="py-4 pl-3">
                    <div className="flex justify-center">
                      <CompareIcon state={row.spotify} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Mobile / small tablet: stacked cards, no horizontal scroll */}
      <div className="mt-10 grid gap-3 sm:grid-cols-2 md:hidden">
        {ROWS.map((row) => (
          <div
            key={row.feature}
            className="ww-card ww-bg-base"
            style={{ border: "1px solid var(--hairline)", padding: "1rem 1.1rem" }}
          >
            <p className="ww-text-1 font-semibold text-base mb-3">
              {row.feature}
            </p>
            <ul className="space-y-2">
              {COLUMNS.map((col, ci) => {
                const state = ci === 0 ? row.ww : ci === 1 ? row.browser : row.spotify;
                const isWW = ci === 0;
                return (
                  <li
                    key={col}
                    className="flex items-center justify-between gap-3"
                  >
                    <span
                      className={`text-sm ${isWW ? "ww-text-brand font-semibold" : "ww-text-2"}`}
                    >
                      {col}
                    </span>
                    <CompareIcon state={state} />
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </div>
    </>
  );
}

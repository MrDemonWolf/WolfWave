"use client";

import { useRef, useState } from "react";
import Link from "next/link";

type TabId = "overlay" | "ha" | "deck";

const TABS: { id: TabId; label: string; lang: string }[] = [
  { id: "overlay", label: "Overlay", lang: "JS" },
  { id: "ha", label: "Home Assistant", lang: "YAML" },
  { id: "deck", label: "Stream Deck", lang: "Node" },
];

const BRAND = "var(--brand-500)";
const DIM = "var(--txt-2)";

function span(color: string, text: string) {
  return `<span style="color:${color}">${text}</span>`;
}

const SNIPPETS: Record<TabId, string> = {
  overlay: [
    `${span(DIM, "// Subscribe to every track change in real time.")}`,
    `${span(BRAND, "const")} ws = ${span(BRAND, "new")} WebSocket(${span(BRAND, '"ws://localhost:8080/now-playing"')});`,
    ``,
    `ws.onmessage = (event) =&gt; {`,
    `  ${span(BRAND, "const")} { title, artist, artwork } = JSON.parse(event.data);`,
    `  document.querySelector(${span(BRAND, '"#title"')}).textContent  = title;`,
    `  document.querySelector(${span(BRAND, '"#artist"')}).textContent = artist;`,
    `  document.querySelector(${span(BRAND, '"#art"')}).src = artwork;`,
    `};`,
  ].join("\n"),

  ha: [
    `${span(DIM, "# configuration.yaml: render the now-playing card on a wall tablet.")}`,
    `sensor:`,
    `  - platform: ${span(BRAND, "rest")}`,
    `    name: ${span(BRAND, '"WolfWave Now Playing"')}`,
    `    resource: ${span(BRAND, "http://mac.local:8080/now-playing.json")}`,
    `    value_template: ${span(BRAND, '"{{ value_json.title }}"')}`,
    `    json_attributes:`,
    `      - artist`,
    `      - album`,
    `      - artwork`,
    `    scan_interval: ${span(BRAND, "5")}`,
  ].join("\n"),

  deck: [
    `${span(DIM, "// Stream Deck plugin: flash the key when a new track lands.")}`,
    `${span(BRAND, "import")} WebSocket ${span(BRAND, "from")} ${span(BRAND, '"ws"')};`,
    ``,
    `${span(BRAND, "const")} ws = ${span(BRAND, "new")} WebSocket(${span(BRAND, '"ws://localhost:8080/now-playing"')});`,
    ``,
    `ws.on(${span(BRAND, '"message"')}, (raw) =&gt; {`,
    `  ${span(BRAND, "const")} { title, artist } = JSON.parse(raw);`,
    `  streamDeck.setTitle(\`\${title}\\n\${artist}\`);`,
    `  streamDeck.flash();`,
    `});`,
  ].join("\n"),
};

export function DeveloperTabs() {
  const [active, setActive] = useState<TabId>("overlay");
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);

  const focusTab = (id: TabId) => {
    setActive(id);
    const idx = TABS.findIndex((t) => t.id === id);
    requestAnimationFrame(() => {
      tabRefs.current[idx]?.focus();
    });
  };

  const onTabKeyDown = (e: React.KeyboardEvent<HTMLButtonElement>) => {
    const idx = TABS.findIndex((t) => t.id === active);
    switch (e.key) {
      case "ArrowRight":
        e.preventDefault();
        focusTab(TABS[(idx + 1) % TABS.length].id);
        break;
      case "ArrowLeft":
        e.preventDefault();
        focusTab(TABS[(idx - 1 + TABS.length) % TABS.length].id);
        break;
      case "Home":
        e.preventDefault();
        focusTab(TABS[0].id);
        break;
      case "End":
        e.preventDefault();
        focusTab(TABS[TABS.length - 1].id);
        break;
    }
  };

  return (
    <div className="ww-dev-terminal">
      {/* status pill */}
      <div className="ww-dev-status-row">
        <span className="ww-dev-status-pill ww-mono">
          <span className="ww-dev-dot" aria-hidden="true" />
          LIVE · ws://localhost:8080
        </span>
      </div>

      {/* window chrome */}
      <div
        className="ww-dev-window"
        style={{ border: "1px solid var(--hairline)" }}
      >
        <div
          className="ww-dev-titlebar"
          style={{
            backgroundColor: "var(--bg-surface)",
            borderBottom: "1px solid var(--hairline)",
          }}
        >
          <div className="ww-dev-lights" aria-hidden="true">
            <span style={{ background: "#ff5f57" }} />
            <span style={{ background: "#febc2e" }} />
            <span style={{ background: "#28c840" }} />
          </div>
          <span className="ww-mono ww-dev-title">wolfwave://now-playing</span>
          <span className="ww-dev-spacer" aria-hidden="true" />
        </div>

        {/* tabs */}
        <div
          role="tablist"
          aria-label="Integration examples"
          className="ww-dev-tabs"
          style={{ borderBottom: "1px solid var(--hairline)" }}
        >
          {TABS.map((tab, idx) => {
            const isActive = active === tab.id;
            return (
              <button
                key={tab.id}
                ref={(el) => {
                  tabRefs.current[idx] = el;
                }}
                role="tab"
                type="button"
                aria-selected={isActive}
                aria-controls={`ww-dev-panel-${tab.id}`}
                id={`ww-dev-tab-${tab.id}`}
                tabIndex={isActive ? 0 : -1}
                onClick={() => setActive(tab.id)}
                onKeyDown={onTabKeyDown}
                className={`ww-dev-tab ww-mono${isActive ? " is-active" : ""}`}
              >
                <span className="ww-dev-tab-label">{tab.label}</span>
                <span className="ww-dev-tab-lang">{tab.lang}</span>
              </button>
            );
          })}
        </div>

        {/* code panel */}
        <div
          role="tabpanel"
          id={`ww-dev-panel-${active}`}
          aria-labelledby={`ww-dev-tab-${active}`}
          className="ww-dev-panel"
        >
          <pre
            className="ww-code ww-dev-code"
            dangerouslySetInnerHTML={{ __html: SNIPPETS[active] }}
          />
        </div>
      </div>

      {/* hint */}
      <p className="ww-dev-hint ww-text-2">
        Need the payload schema?{" "}
        <Link href="/docs/architecture" className="ww-text-brand font-semibold">
          Read the architecture →
        </Link>
      </p>

      <style jsx>{`
        .ww-dev-terminal {
          position: relative;
        }
        .ww-dev-status-row {
          display: flex;
          justify-content: flex-end;
          margin-bottom: 10px;
        }
        .ww-dev-status-pill {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 4px 10px;
          font-size: 11px;
          letter-spacing: 0.04em;
          color: var(--txt-2);
          background: var(--bg-surface);
          border: 1px solid var(--hairline);
          border-radius: 999px;
        }
        .ww-dev-dot {
          width: 7px;
          height: 7px;
          border-radius: 999px;
          background: #28c840;
          box-shadow: 0 0 0 0 rgba(40, 200, 64, 0.55);
        }
        @media (prefers-reduced-motion: no-preference) {
          .ww-dev-dot {
            animation: wwDevPulse 1.8s ease-out infinite;
          }
        }
        @keyframes wwDevPulse {
          0% {
            box-shadow: 0 0 0 0 rgba(40, 200, 64, 0.55);
          }
          70% {
            box-shadow: 0 0 0 9px rgba(40, 200, 64, 0);
          }
          100% {
            box-shadow: 0 0 0 0 rgba(40, 200, 64, 0);
          }
        }
        .ww-dev-window {
          border-radius: 16px;
          overflow: hidden;
          background: var(--bg-base);
        }
        .ww-dev-titlebar {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 14px;
        }
        .ww-dev-lights {
          display: inline-flex;
          gap: 6px;
        }
        .ww-dev-lights span {
          width: 11px;
          height: 11px;
          border-radius: 999px;
          display: inline-block;
        }
        .ww-dev-title {
          flex: 1;
          text-align: center;
          font-size: 11px;
          color: var(--txt-2);
          letter-spacing: 0.02em;
        }
        .ww-dev-spacer {
          width: 39px; /* mirror the lights cluster so the title stays centered */
        }
        .ww-dev-tabs {
          display: flex;
          overflow-x: auto;
          scrollbar-width: none;
        }
        .ww-dev-tabs::-webkit-scrollbar {
          display: none;
        }
        .ww-dev-tab {
          appearance: none;
          background: transparent;
          border: 0;
          border-right: 1px solid var(--hairline);
          padding: 12px 16px;
          color: var(--txt-2);
          font-size: 12px;
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          gap: 8px;
          transition: color 150ms ease, background-color 150ms ease;
          white-space: nowrap;
        }
        .ww-dev-tab:hover {
          color: var(--txt-1);
          background-color: color-mix(in srgb, var(--bg-surface) 50%, transparent);
        }
        .ww-dev-tab.is-active {
          color: var(--txt-1);
          background: var(--bg-base);
          box-shadow: inset 0 -2px 0 0 var(--brand-500);
        }
        .ww-dev-tab-lang {
          font-size: 10px;
          letter-spacing: 0.06em;
          color: var(--txt-2);
          padding: 2px 6px;
          border-radius: 4px;
          background: var(--bg-surface);
        }
        .ww-dev-tab.is-active .ww-dev-tab-lang {
          color: var(--brand-500);
          background: var(--brand-50);
        }
        .ww-dev-panel {
          opacity: 0;
          animation: wwDevFade 180ms ease forwards;
        }
        @keyframes wwDevFade {
          to {
            opacity: 1;
          }
        }
        .ww-dev-code {
          margin: 0;
          border-radius: 0;
          border: 0;
        }
        .ww-dev-hint {
          text-align: center;
          font-size: 13px;
          margin-top: 14px;
        }
      `}</style>
    </div>
  );
}

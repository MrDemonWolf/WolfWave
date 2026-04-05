import satori from "satori";
import { Resvg } from "@resvg/resvg-js";
import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");

// Load a font — use system Inter or download one
const fontPath = join(root, "node_modules", "satori", "vendor", "noto-sans-v27-latin-regular.ttf");
let fontData;
try {
  fontData = readFileSync(fontPath);
} catch {
  // Fallback: fetch Inter from Google Fonts CDN
  const res = await fetch(
    "https://fonts.gstatic.com/s/inter/v18/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZhrib2Bg-4.ttf"
  );
  fontData = Buffer.from(await res.arrayBuffer());
}

// Bold font
let fontBoldData;
try {
  const boldPath = join(root, "node_modules", "satori", "vendor", "noto-sans-v27-latin-700.ttf");
  fontBoldData = readFileSync(boldPath);
} catch {
  const res = await fetch(
    "https://fonts.gstatic.com/s/inter/v18/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZhrib2Bg-4.ttf"
  );
  fontBoldData = Buffer.from(await res.arrayBuffer());
}

const svg = await satori(
  {
    type: "div",
    props: {
      style: {
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        background: "linear-gradient(135deg, #080810 0%, #0e0e1a 50%, #080810 100%)",
        position: "relative",
        fontFamily: "Inter",
      },
      children: [
        // Gradient glow
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: "0",
              left: "50%",
              transform: "translateX(-50%)",
              width: "800px",
              height: "400px",
              background:
                "radial-gradient(ellipse at center, rgba(124, 58, 237, 0.2) 0%, rgba(34, 211, 238, 0.08) 45%, transparent 70%)",
              display: "flex",
            },
          },
        },
        // Version badge
        {
          type: "div",
          props: {
            style: {
              display: "flex",
              alignItems: "center",
              gap: "8px",
              padding: "6px 16px",
              borderRadius: "999px",
              border: "1px solid rgba(124, 58, 237, 0.4)",
              backgroundColor: "rgba(124, 58, 237, 0.08)",
              color: "#a855f7",
              fontSize: "16px",
              fontWeight: 600,
              marginBottom: "24px",
            },
            children: "v1.2.0 — Free & Open Source",
          },
        },
        // Title container
        {
          type: "div",
          props: {
            style: {
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: "4px",
            },
            children: [
              {
                type: "span",
                props: {
                  style: {
                    fontSize: "64px",
                    fontWeight: 700,
                    background: "linear-gradient(135deg, #7c3aed, #22d3ee, #a855f7)",
                    backgroundClip: "text",
                    color: "transparent",
                    lineHeight: 1.1,
                  },
                  children: "Your Music,",
                },
              },
              {
                type: "span",
                props: {
                  style: {
                    fontSize: "64px",
                    fontWeight: 700,
                    color: "#FFFFFF",
                    lineHeight: 1.1,
                  },
                  children: "Live Everywhere.",
                },
              },
            ],
          },
        },
        // Subtitle
        {
          type: "div",
          props: {
            style: {
              fontSize: "22px",
              color: "#94a3b8",
              marginTop: "20px",
              textAlign: "center",
              maxWidth: "600px",
              display: "flex",
            },
            children:
              "macOS menu bar app for Apple Music — Twitch, Discord, and stream overlays update automatically.",
          },
        },
        // Bottom bar
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              bottom: "32px",
              display: "flex",
              alignItems: "center",
              gap: "24px",
            },
            children: ["Twitch Chat Bot", "Discord Status", "Stream Overlay", "Open Source"].map(
              (item) => ({
                type: "span",
                props: {
                  style: {
                    fontSize: "14px",
                    color: "#64748b",
                    padding: "4px 12px",
                    borderRadius: "999px",
                    border: "1px solid rgba(124, 58, 237, 0.2)",
                    backgroundColor: "rgba(124, 58, 237, 0.06)",
                  },
                  children: item,
                },
              })
            ),
          },
        },
      ],
    },
  },
  {
    width: 1200,
    height: 630,
    fonts: [
      { name: "Inter", data: fontData, weight: 400, style: "normal" },
      { name: "Inter", data: fontBoldData, weight: 700, style: "normal" },
    ],
  }
);

const resvg = new Resvg(svg, {
  fitTo: { mode: "width", value: 1200 },
});
const pngData = resvg.render();
const pngBuffer = pngData.asPng();

const outPath = join(root, "apps", "docs", "public", "og-image.png");
writeFileSync(outPath, pngBuffer);
console.log(`OG image written to ${outPath} (${(pngBuffer.length / 1024).toFixed(1)} KB)`);

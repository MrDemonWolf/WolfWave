import { ImageResponse } from "next/og";
import { OgCard, OG_SIZE, OG_CONTENT_TYPE, loadOgFonts } from "./og/_components/og-card";

export const alt = "WolfWave. Free macOS app connecting Apple Music to Twitch, Discord, and stream overlays.";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;
export const dynamic = "force-static";
export const revalidate = false;

export default async function Image() {
  const fonts = await loadOgFonts();
  return new ImageResponse(
    (
      <OgCard
        eyebrow="v2.0.0 · Free & Open Source"
        title="Your Music, Live Everywhere."
        accentWord="Everywhere."
        description="A tiny macOS menu bar app. Play in Apple Music, and Twitch chat, Discord, and your overlay all update on their own."
        chips={["Twitch Chat Bot", "Discord Status", "Stream Overlay", "Open Source"]}
      />
    ),
    {
      ...size,
      fonts: fonts.map((f) => ({ name: f.name, data: f.data, weight: f.weight as 400 | 500 | 700, style: f.style })),
    },
  );
}

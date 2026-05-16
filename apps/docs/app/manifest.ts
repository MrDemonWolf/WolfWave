import type { MetadataRoute } from "next";
import { basePath } from "@/lib/site";

export const dynamic = "force-static";
export const revalidate = false;

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "WolfWave — Your Music, Live Everywhere",
    short_name: "WolfWave",
    description:
      "Free macOS menu bar app that shares your Apple Music now-playing to Twitch chat, Discord Rich Presence, and OBS stream overlays.",
    start_url: `${basePath || ""}/`,
    scope: `${basePath || ""}/`,
    display: "standalone",
    background_color: "#000000",
    theme_color: "#0A84FF",
    icons: [
      { src: `${basePath}/icon.svg`, sizes: "any", type: "image/svg+xml" },
      { src: `${basePath}/icon.png`, sizes: "512x512", type: "image/png", purpose: "any" },
      { src: `${basePath}/apple-icon.png`, sizes: "180x180", type: "image/png", purpose: "any" },
    ],
  };
}

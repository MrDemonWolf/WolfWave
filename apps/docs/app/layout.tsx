import { Unbounded, Instrument_Sans, Instrument_Serif, JetBrains_Mono } from "next/font/google";
import type { Metadata } from "next";
import { Provider } from "@/components/provider";
import { siteUrl, basePath } from "@/lib/site";
import "./global.css";

const unbounded = Unbounded({
  subsets: ["latin"],
  variable: "--font-unbounded",
  display: "swap",
});

const instrumentSans = Instrument_Sans({
  subsets: ["latin"],
  variable: "--font-instrument",
  display: "swap",
});

const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-serif",
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "WolfWave — Your Music, Live Everywhere",
    template: "%s | WolfWave",
  },
  description:
    "Free macOS menu bar app that shares your Apple Music now-playing to Twitch chat, Discord Rich Presence, and OBS stream overlays — automatically.",
  keywords: [
    "WolfWave",
    "Apple Music",
    "Twitch",
    "Discord",
    "Rich Presence",
    "macOS",
    "menu bar",
    "now playing",
    "stream overlay",
    "OBS",
    "chat bot",
    "WebSocket",
    "open source",
    "free",
    "streamer tools",
  ],
  authors: [{ name: "MrDemonWolf, Inc." }],
  creator: "MrDemonWolf, Inc.",
  icons: {
    icon: [
      { url: `${basePath}/icon.svg`, type: "image/svg+xml" },
      { url: `${basePath}/icon.png`, type: "image/png" },
    ],
    apple: `${basePath}/apple-icon.png`,
  },
  alternates: {
    canonical: siteUrl,
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    url: siteUrl,
    siteName: "WolfWave",
    title: "WolfWave — Your Music, Live Everywhere",
    description:
      "WolfWave is a free, open-source macOS menu bar app that broadcasts your Apple Music to Twitch chat, Discord Rich Presence, and stream overlays via WebSocket. No account required.",
  },
  twitter: {
    card: "summary_large_image",
    site: "@mrdemonwolf",
    creator: "@mrdemonwolf",
    title: "WolfWave — Your Music, Live Everywhere",
    description:
      "Free macOS menu bar app that shares your Apple Music now-playing to Twitch chat, Discord Rich Presence, and OBS stream overlays — automatically.",
  },
  metadataBase: new URL(siteUrl),
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "WolfWave",
  description:
    "Free macOS menu bar app that shares your Apple Music now-playing to Twitch chat, Discord Rich Presence, and OBS stream overlays — automatically.",
  operatingSystem: "macOS 26.0",
  applicationCategory: "MultimediaApplication",
  applicationSubCategory: "Streaming",
  processorRequirements: "Apple Silicon",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
  author: {
    "@type": "Organization",
    name: "MrDemonWolf, Inc.",
    url: "https://github.com/mrdemonwolf",
  },
  publisher: {
    "@type": "Organization",
    name: "MrDemonWolf, Inc.",
    url: "https://github.com/mrdemonwolf",
  },
  url: siteUrl,
  downloadUrl: "https://github.com/mrdemonwolf/wolfwave/releases/latest",
  installUrl: `${siteUrl}/download/`,
  softwareVersion: "2.0.0",
  releaseNotes: `${siteUrl}/docs/changelog/`,
  screenshot: `${siteUrl}/opengraph-image`,
  featureList: [
    "Apple Music now-playing to Twitch chat (!song, !last)",
    "Twitch song requests for Apple Music (!sr) with channel points and bits",
    "Discord Rich Presence — Listening to Apple Music",
    "OBS browser-source overlay with 6 themes and 3 layouts",
    "Vote-to-skip via chat or Twitch Polls",
    "macOS menu bar app — no account required",
  ],
  license: "https://github.com/mrdemonwolf/wolfwave/blob/main/LICENSE",
};

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${unbounded.variable} ${instrumentSans.variable} ${instrumentSerif.variable} ${jetbrainsMono.variable}`} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <a href="#nd-page" className="skip-nav">
          Skip to content
        </a>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}

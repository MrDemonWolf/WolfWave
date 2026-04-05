import { Unbounded, Instrument_Sans } from "next/font/google";
import type { Metadata } from "next";
import { Provider } from "@/components/provider";
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

const siteUrl = "https://mrdemonwolf.github.io/wolfwave";

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
      { url: "/icon.svg", type: "image/svg+xml" },
      { url: "/icon.png", type: "image/png" },
    ],
    apple: "/apple-icon.png",
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
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "WolfWave — free macOS app connecting Apple Music to Twitch, Discord, and stream overlays",
      },
    ],
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
  operatingSystem: "macOS",
  applicationCategory: "MultimediaApplication",
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
  url: siteUrl,
  downloadUrl: "https://github.com/mrdemonwolf/wolfwave/releases/latest",
  softwareVersion: "1.2.0",
  license: "https://github.com/mrdemonwolf/wolfwave/blob/main/LICENSE",
};

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${unbounded.variable} ${instrumentSans.variable}`} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}

import { Unbounded, Instrument_Sans, Instrument_Serif, JetBrains_Mono } from "next/font/google";
import type { Metadata } from "next";
import { Provider } from "@/components/provider";
import { siteUrl, basePath, absoluteUrl, homepageSeo, repoUrl, orgUrl, getLatestVersion } from "@/lib/site";
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
    default: homepageSeo.title,
    template: "%s | WolfWave",
  },
  description: homepageSeo.description,
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
    title: homepageSeo.title,
    description: homepageSeo.socialDescription,
    images: [
      {
        url: absoluteUrl("/opengraph-image.png"),
        width: 1200,
        height: 630,
        alt: homepageSeo.ogImageAlt,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: "@mrdemonwolf",
    creator: "@mrdemonwolf",
    title: homepageSeo.title,
    description: homepageSeo.socialDescription,
    images: [absoluteUrl("/opengraph-image.png")],
  },
  metadataBase: new URL(siteUrl),
};

function buildJsonLd(softwareVersion: string | null) {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "WolfWave",
    description: homepageSeo.description,
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
      url: orgUrl,
    },
    publisher: {
      "@type": "Organization",
      name: "MrDemonWolf, Inc.",
      url: orgUrl,
    },
    url: siteUrl,
    downloadUrl: `${repoUrl}/releases/latest`,
    installUrl: `${siteUrl}/download/`,
    // Derived from the latest GitHub release at build time; omitted entirely
    // when the fetch fails so we never ship a stale hardcoded version.
    ...(softwareVersion ? { softwareVersion } : {}),
    releaseNotes: `${siteUrl}/docs/changelog/`,
    screenshot: `${siteUrl}/opengraph-image`,
    featureList: [
      "Apple Music now-playing to Twitch chat (!song, !last)",
      "Twitch song requests for Apple Music (!sr) with channel points and bits",
      "Discord Rich Presence, Listening to WolfWave with Apple Music album art",
      "OBS browser-source overlay with 6 themes and 3 layouts",
      "Vote-to-skip via chat or Twitch Polls",
      "macOS menu bar app",
    ],
    license: `${repoUrl}/blob/main/LICENSE`,
  };
}

export default async function Layout({ children }: LayoutProps<"/">) {
  const jsonLd = buildJsonLd(await getLatestVersion());
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

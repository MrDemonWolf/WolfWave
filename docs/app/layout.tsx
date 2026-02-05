import { Inter } from "next/font/google";
import type { Metadata } from "next";
import { Provider } from "@/components/provider";
import "./global.css";

const inter = Inter({
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: {
    default: "WolfWave - Apple Music + Twitch Companion",
    template: "%s | WolfWave",
  },
  description:
    "Professional macOS menu bar utility that connects Apple Music with your Twitch audience via WebSockets and secure chat commands.",
  keywords: [
    "WolfWave",
    "Apple Music",
    "Twitch",
    "macOS",
    "menu bar",
    "WebSocket",
    "now playing",
    "stream overlay",
    "chat bot",
  ],
  authors: [{ name: "MrDemonWolf, Inc." }],
  creator: "MrDemonWolf, Inc.",
  openGraph: {
    type: "website",
    locale: "en_US",
    siteName: "WolfWave",
    title: "WolfWave - Apple Music + Twitch Companion",
    description:
      "Professional macOS menu bar utility that connects Apple Music with your Twitch audience via WebSockets and secure chat commands.",
  },
  twitter: {
    card: "summary_large_image",
    title: "WolfWave - Apple Music + Twitch Companion",
    description:
      "Professional macOS menu bar utility that connects Apple Music with your Twitch audience via WebSockets and secure chat commands.",
  },
  metadataBase: new URL("https://wolfwave.mdwolf.net"),
};

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={inter.className} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}

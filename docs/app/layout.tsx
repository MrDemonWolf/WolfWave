import { Inter } from "next/font/google";
import type { Metadata } from "next";
import { Provider } from "@/components/provider";
import "./global.css";

const inter = Inter({
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: {
    default: "WolfWave - Your Music, Everywhere",
    template: "%s | WolfWave",
  },
  description:
    "Professional macOS menu bar utility that bridges Apple Music with Twitch, Discord, and your stream overlays.",
  keywords: [
    "WolfWave",
    "Apple Music",
    "Twitch",
    "Discord",
    "Rich Presence",
    "macOS",
    "menu bar",
    "WebSocket",
    "now playing",
    "stream overlay",
    "chat bot",
  ],
  authors: [{ name: "MrDemonWolf, Inc." }],
  creator: "MrDemonWolf, Inc.",
  icons: {
    icon: "/icon.png",
    apple: "/apple-icon.png",
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    siteName: "WolfWave",
    title: "WolfWave - Your Music, Everywhere",
    description:
      "Professional macOS menu bar utility that bridges Apple Music with Twitch, Discord, and your stream overlays.",
  },
  twitter: {
    card: "summary_large_image",
    title: "WolfWave - Your Music, Everywhere",
    description:
      "Professional macOS menu bar utility that bridges Apple Music with Twitch, Discord, and your stream overlays.",
  },
  metadataBase: new URL("https://mrdemonwolf.github.io/wolfwave"),
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

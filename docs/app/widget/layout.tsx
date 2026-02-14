import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Now Playing Widget | WolfWave",
  description: "Stream overlay widget for displaying now-playing music info.",
  robots: "noindex, nofollow",
};

export default function WidgetLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}

import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: "WolfWave",
      url: "/",
      transparentMode: "top",
    },
    githubUrl: "https://github.com/MrDemonWolf/WolfWave",
    links: [
      { text: "Docs", url: "/docs" },
      { text: "Features", url: "/docs/features" },
      { text: "Twitch", url: "/docs/twitch" },
      { text: "Support", url: "https://mrdwolf.com/discord" },
    ],
    themeSwitch: {
      enabled: true,
      mode: "light-dark-system",
    },
    searchToggle: {
      enabled: true,
    },
  };
}

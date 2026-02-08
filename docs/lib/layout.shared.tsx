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
      { text: "Support", url: "https://mdwolf.net/discord" },
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

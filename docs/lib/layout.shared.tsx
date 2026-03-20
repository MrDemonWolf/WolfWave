import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { getAssetPath } from "@/lib/utils";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <div className="flex items-center gap-2">
          <img src={getAssetPath("/logo-light.png")} alt="WolfWave" className="h-6 w-auto dark:hidden" />
          <img src={getAssetPath("/logo-dark.png")} alt="WolfWave" className="h-6 w-auto hidden dark:block" />
          <span className="font-bold text-lg tracking-tight">WolfWave</span>
        </div>
      ),
      url: "/",
      transparentMode: "top",
    },
    githubUrl: "https://github.com/MrDemonWolf/WolfWave",
    links: [
      { text: "Docs", url: "/docs" },
      { text: "Support", url: "https://mrdwolf.net/discord" },
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

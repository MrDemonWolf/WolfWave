import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { getAssetPath } from "@/lib/utils";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <span data-ww-brand className="inline-flex items-center gap-2.5">
          <img
            src={getAssetPath("/logo.svg")}
            alt=""
            aria-hidden="true"
            className="h-7 w-auto"
          />
          <span className="font-[var(--font-unbounded)] text-[1.05rem] font-semibold tracking-tight text-[var(--txt-1)]">
            WolfWave
          </span>
        </span>
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

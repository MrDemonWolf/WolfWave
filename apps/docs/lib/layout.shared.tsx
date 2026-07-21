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
          <span className="font-[var(--font-instrument)] text-[1.05rem] font-semibold tracking-tight text-[var(--txt-1)]">
            WolfWave
          </span>
        </span>
      ),
      url: "/",
      transparentMode: "top",
    },
    githubUrl: "https://github.com/MrDemonWolf/WolfWave",
    links: [
      // Landing-section anchors. On the home page these scroll; from any other
      // page they navigate home and then jump to the section.
      { text: "Features", url: "/#audiences" },
      { text: "Compare", url: "/#compare" },
      { text: "FAQ", url: "/#faq" },
      // Real pages. `active: nested-url` keeps the item lit on the page and its
      // children, so the nav always shows where you are.
      { text: "Docs", url: "/docs", active: "nested-url" },
      // Primary conversion, kept last for recall (serial-position effect).
      { text: "Download", url: "/download", active: "url" },
      // Single community link. External Discord, opens in a new tab.
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

import Link from "next/link";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  const currentYear = new Date().getFullYear();
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer
        className="ww-font ww-bg-base"
        style={{ borderTop: "1px solid var(--hairline)" }}
      >
        <div className="mx-auto max-w-6xl px-[10%] md:px-6 py-10 flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-sm ww-text-2">
            &copy; {currentYear} WolfWave by{" "}
            <a
              href="https://www.mrdemonwolf.com"
              target="_blank"
              rel="noopener noreferrer"
              className="ww-text-1 hover:underline"
              style={{ textUnderlineOffset: 3 }}
            >
              MrDemonWolf, Inc.
            </a>
          </p>
          <nav className="flex items-center gap-6 text-sm ww-text-2">
            <a
              href="https://github.com/MrDemonWolf/WolfWave"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:ww-text-1 transition-colors"
            >
              GitHub
            </a>
            <a
              href="https://mrdwolf.net/discord"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:ww-text-1 transition-colors"
            >
              Discord
            </a>
            <Link href="/docs" className="hover:ww-text-1 transition-colors">
              Docs
            </Link>
            <Link
              href="/docs/privacy-policy"
              className="hover:ww-text-1 transition-colors"
            >
              Privacy
            </Link>
          </nav>
        </div>
      </footer>
    </HomeLayout>
  );
}

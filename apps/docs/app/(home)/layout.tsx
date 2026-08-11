import Link from "next/link";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";
import { repoUrl } from "@/lib/site";

/**
 * The commit this build came from. CI passes `NEXT_PUBLIC_COMMIT_SHA`; the bare
 * `GITHUB_SHA` is the fallback for any workflow that forgets to. Undefined
 * locally, where there is no deploy to point at.
 */
const commitSha = process.env.NEXT_PUBLIC_COMMIT_SHA ?? process.env.GITHUB_SHA;

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
            {commitSha ? (
              <>
                {" · built from "}
                <a
                  href={`${repoUrl}/commit/${commitSha}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="ww-text-1 hover:underline font-mono"
                  style={{ textUnderlineOffset: 3 }}
                >
                  {commitSha.slice(0, 7)}
                </a>
              </>
            ) : null}
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

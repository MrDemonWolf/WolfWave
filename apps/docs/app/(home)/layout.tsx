import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  const currentYear = new Date().getFullYear();
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer className="border-t border-slate-200 dark:border-slate-800">
        <div className="mx-auto max-w-4xl px-6 py-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-xs text-slate-500 dark:text-slate-500">
            &copy; {currentYear} WolfWave by MrDemonWolf, Inc.
          </p>
          <nav className="flex items-center gap-5">
            <a
              href="https://github.com/MrDemonWolf/WolfWave"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors"
            >
              GitHub
            </a>
            <a
              href="https://mrdwolf.net/discord"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors"
            >
              Discord
            </a>
            <a
              href="/docs"
              className="text-xs text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors"
            >
              Docs
            </a>
          </nav>
        </div>
      </footer>
    </HomeLayout>
  );
}

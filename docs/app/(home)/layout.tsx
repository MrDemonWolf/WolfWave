import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  const currentYear = new Date().getFullYear();
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer className="mt-12 py-8 text-center text-sm text-slate-500 dark:text-slate-400">
        © {currentYear} WaveWave by MrDemonWolf, Inc.
      </footer>
    </HomeLayout>
  );
}

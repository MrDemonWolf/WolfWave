import type { MetadataRoute } from "next";
import { statSync } from "node:fs";
import { source } from "@/lib/source";
import { siteUrl } from "@/lib/site";

export const dynamic = "force-static";
export const revalidate = false;

type Freq = MetadataRoute.Sitemap[number]["changeFrequency"];

function classify(url: string): { priority: number; changeFrequency: Freq } {
  if (url === "/") return { priority: 1.0, changeFrequency: "monthly" };
  if (url === "/docs" || url === "/docs/") return { priority: 0.9, changeFrequency: "weekly" };
  if (url.includes("/changelog")) return { priority: 0.9, changeFrequency: "weekly" };
  if (url.includes("/privacy-policy") || url.includes("/terms-of-service")) {
    return { priority: 0.5, changeFrequency: "monthly" };
  }
  return { priority: 0.7, changeFrequency: "weekly" };
}

function abs(p: string): string {
  const clean = p.endsWith("/") ? p : `${p}/`;
  return `${siteUrl}${clean === "/" ? "/" : clean}`;
}

function mtime(absPath: string | undefined): Date {
  if (!absPath) return new Date();
  try {
    return statSync(absPath).mtime;
  } catch {
    return new Date();
  }
}

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  const staticEntries: MetadataRoute.Sitemap = [
    {
      url: abs("/"),
      lastModified: now,
      ...classify("/"),
    },
    {
      url: abs("/widget"),
      lastModified: now,
      priority: 0.4,
      changeFrequency: "monthly",
    },
  ];

  const docEntries: MetadataRoute.Sitemap = source.getPages().map((page) => ({
    url: abs(page.url),
    lastModified: mtime((page as { absolutePath?: string }).absolutePath),
    ...classify(page.url),
  }));

  return [...staticEntries, ...docEntries];
}

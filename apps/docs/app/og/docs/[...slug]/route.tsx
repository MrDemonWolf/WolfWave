import { getPageImage, source } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import {
  OgCard,
  ChangelogOgCard,
  OG_SIZE,
  loadOgFonts,
} from '../../_components/og-card';
import { presetForSlug } from '../../_components/og-presets';

export const revalidate = false;

interface ChangelogInfo {
  version: string;
  date: string;
  highlights: string[];
}

function parseLatestChangelog(): ChangelogInfo | null {
  try {
    const filePath = path.join(process.cwd(), 'content/docs/changelog.mdx');
    const raw = readFileSync(filePath, 'utf-8');
    const versionMatch = raw.match(/^##\s+v(\d[\d.]*)\s*[—–-]\s*(.+)$/m);
    if (!versionMatch) return null;
    const version = versionMatch[1];
    const date = versionMatch[2].trim();

    const after = raw.slice(versionMatch.index! + versionMatch[0].length);
    const next = after.search(/^##\s+v\d/m);
    const section = next === -1 ? after : after.slice(0, next);

    const bulletRe = /^[-*]\s+\*\*([^*]+)\*\*/gm;
    const highlights: string[] = [];
    let m: RegExpExecArray | null;
    while ((m = bulletRe.exec(section)) !== null && highlights.length < 3) {
      highlights.push(m[1].trim());
    }
    if (highlights.length === 0) return null;
    return { version, date, highlights };
  } catch {
    return null;
  }
}

export async function GET(_req: Request, { params }: RouteContext<'/og/docs/[...slug]'>) {
  const { slug } = await params;
  const pageSlug = slug.slice(0, -1);
  const page = source.getPage(pageSlug);
  if (!page) notFound();

  const fonts = await loadOgFonts();
  const preset = presetForSlug(pageSlug);
  const isChangelog = pageSlug[0] === 'changelog';

  const chips = page.data.ogChips ?? preset.chips;
  const eyebrow = page.data.ogEyebrow ?? preset.eyebrow;

  if (isChangelog) {
    const cl = parseLatestChangelog();
    if (cl) {
      return new ImageResponse(
        <ChangelogOgCard version={cl.version} date={cl.date} highlights={cl.highlights} />,
        {
          ...OG_SIZE,
          fonts: fonts.map((f) => ({ name: f.name, data: f.data, weight: f.weight as 400 | 500 | 700, style: f.style })),
        },
      );
    }
  }

  return new ImageResponse(
    (
      <OgCard
        eyebrow={eyebrow}
        title={page.data.ogTitle ?? page.data.title}
        description={page.data.ogDescription ?? page.data.description}
        chips={chips}
      />
    ),
    {
      ...OG_SIZE,
      fonts: fonts.map((f) => ({ name: f.name, data: f.data, weight: f.weight as 400 | 500 | 700, style: f.style })),
    },
  );
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({
    lang: page.locale,
    slug: getPageImage(page).segments,
  }));
}

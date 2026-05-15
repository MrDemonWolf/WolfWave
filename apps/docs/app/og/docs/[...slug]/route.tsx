import { getPageImage, source } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';
import { OgCard, OG_SIZE, loadOgFonts } from '../../_components/og-card';

export const revalidate = false;

export async function GET(_req: Request, { params }: RouteContext<'/og/docs/[...slug]'>) {
  const { slug } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  const fonts = await loadOgFonts();

  return new ImageResponse(
    (
      <OgCard
        eyebrow="WolfWave Docs"
        title={page.data.title}
        description={page.data.description}
      />
    ),
    {
      ...OG_SIZE,
      fonts: fonts.map((f) => ({ name: f.name, data: f.data, weight: f.weight as 400 | 500 | 600, style: f.style })),
    },
  );
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({
    lang: page.locale,
    slug: getPageImage(page).segments,
  }));
}

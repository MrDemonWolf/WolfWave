import { getPageImage, source } from '@/lib/source';
import { DocsBody, DocsDescription, DocsPage, DocsTitle } from 'fumadocs-ui/layouts/docs/page';
import { notFound } from 'next/navigation';
import { getMDXComponents } from '@/mdx-components';
import type { Metadata } from 'next';
import { createRelativeLink } from 'fumadocs-ui/mdx';
import { siteUrl } from '@/lib/site';
import { presetForSlug } from '@/app/og/_components/og-presets';

function sectionLabel(slug: string[] | undefined): string | null {
  if (!slug || slug.length === 0) return null;
  return presetForSlug(slug).eyebrow;
}

export default async function Page(props: PageProps<'/docs/[[...slug]]'>) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const slug = params.slug?.join('/') ?? '';
  const pageUrl = `${siteUrl}/docs/${slug ? `${slug}/` : ''}`;
  const section = sectionLabel(params.slug);

  const breadcrumbItems = [
    { name: 'Home', item: `${siteUrl}/` },
    { name: 'Docs', item: `${siteUrl}/docs/` },
    ...(section ? [{ name: section, item: pageUrl }] : []),
  ];

  const articleLd = {
    '@context': 'https://schema.org',
    '@type': 'TechArticle',
    headline: page.data.title,
    description: page.data.description,
    inLanguage: 'en-US',
    isPartOf: { '@type': 'WebSite', name: 'WolfWave', url: siteUrl },
    author: { '@type': 'Organization', name: 'MrDemonWolf, Inc.', url: 'https://github.com/mrdemonwolf' },
    publisher: { '@type': 'Organization', name: 'MrDemonWolf, Inc.' },
    mainEntityOfPage: pageUrl,
    url: pageUrl,
  };

  const breadcrumbLd = {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: breadcrumbItems.map((b, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: b.name,
      item: b.item,
    })),
  };

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(articleLd) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbLd) }}
      />
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            // this allows you to link to other pages with relative file paths
            a: createRelativeLink(source, page),
          })}
        />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

const GLOBAL_KEYWORDS = [
  'WolfWave',
  'Apple Music',
  'Twitch',
  'Discord',
  'macOS',
  'menu bar',
  'now playing',
  'stream overlay',
  'OBS',
  'open source',
];

export async function generateMetadata(props: PageProps<'/docs/[[...slug]]'>): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const slug = params.slug?.join('/') ?? '';
  const pageUrl = `${siteUrl}/docs/${slug ? `${slug}/` : ''}`;
  const ogImage = getPageImage(page).url;
  const alt = `${page.data.title} — WolfWave docs`;
  const pageKeywords = page.data.keywords ?? [];

  return {
    title: page.data.title,
    description: page.data.description,
    keywords: [...new Set([...pageKeywords, ...GLOBAL_KEYWORDS])],
    alternates: {
      canonical: pageUrl,
    },
    openGraph: {
      type: 'article',
      url: pageUrl,
      siteName: 'WolfWave',
      title: page.data.title,
      description: page.data.description,
      images: [
        {
          url: ogImage,
          width: 1200,
          height: 630,
          alt,
        },
      ],
    },
    twitter: {
      card: 'summary_large_image',
      site: '@mrdemonwolf',
      creator: '@mrdemonwolf',
      title: page.data.title,
      description: page.data.description,
      images: [ogImage],
    },
  };
}

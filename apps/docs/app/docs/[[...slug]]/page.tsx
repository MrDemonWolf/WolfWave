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

  const slugRoot = params.slug?.[0];

  const howToLd =
    slugRoot === 'installation'
      ? {
          '@context': 'https://schema.org',
          '@type': 'HowTo',
          name: 'Install WolfWave on macOS',
          description:
            'Install WolfWave — the free Apple Music to Twitch, Discord, and OBS bridge — on macOS in under two minutes.',
          totalTime: 'PT2M',
          supply: [
            { '@type': 'HowToSupply', name: 'Mac running macOS 26.0 or later' },
            { '@type': 'HowToSupply', name: 'Apple Music app' },
          ],
          tool: [{ '@type': 'HowToTool', name: 'Homebrew (optional)' }],
          step: [
            {
              '@type': 'HowToStep',
              position: 1,
              name: 'Download WolfWave',
              text: 'Download the latest WolfWave.dmg from GitHub Releases, or run `brew install --cask wolfwave`.',
              url: `${siteUrl}/download/`,
            },
            {
              '@type': 'HowToStep',
              position: 2,
              name: 'Move to Applications',
              text: 'Open the DMG and drag WolfWave to your Applications folder.',
            },
            {
              '@type': 'HowToStep',
              position: 3,
              name: 'Grant Apple Music access',
              text: 'Launch WolfWave from the menu bar and approve the Apple Music automation prompt.',
            },
            {
              '@type': 'HowToStep',
              position: 4,
              name: 'Connect Twitch and Discord',
              text: 'Sign in to Twitch (Device Code) and enable Discord Rich Presence in Settings.',
            },
          ],
        }
      : null;

  const faqByPage: Record<string, Array<{ q: string; a: string }>> = {
    usage: [
      {
        q: 'How do I show what I am listening to in Apple Music on Twitch?',
        a: 'Install WolfWave, sign in to Twitch, and enable the !song command. Chat replies with the live Apple Music track.',
      },
      {
        q: 'Do I need a Spotify account or premium?',
        a: 'No. WolfWave reads directly from Apple Music on macOS — no Spotify, no premium, no extra subscription.',
      },
      {
        q: 'How do Twitch song requests work?',
        a: 'Enable Song Requests in WolfWave. Viewers type !sr <song name or Apple Music link> in chat and the track is added to the Apple Music queue.',
      },
      {
        q: 'Can I show Apple Music in my Discord profile?',
        a: 'Yes. WolfWave broadcasts Apple Music to Discord Rich Presence so your status reads "Listening to WolfWave" with the track, album, and Apple Music album art.',
      },
      {
        q: 'Does WolfWave work as an OBS overlay?',
        a: 'Yes. WolfWave runs a local WebSocket + HTTP widget you add to OBS as a Browser Source. Six themes, three layouts.',
      },
    ],
    support: [
      {
        q: 'Is WolfWave free?',
        a: 'Yes. WolfWave is free and open source under the MIT license. No accounts, no paywalls, no ads.',
      },
      {
        q: 'Does WolfWave track me or send data to servers?',
        a: 'No. WolfWave has no analytics and no servers. Tokens live in your macOS Keychain. Now-playing data goes only to the services you enable.',
      },
      {
        q: 'How can I support the project?',
        a: 'Sponsor MrDemonWolf on GitHub Sponsors, star the repo, or contribute a pull request.',
      },
    ],
    'bot-commands': [
      {
        q: 'What chat commands does WolfWave support?',
        a: '!song / !nowplaying for the current track, !last for the previous track, !sr to request a song, !queue and !myqueue to view the queue, !skip and !voteskip to skip.',
      },
      {
        q: 'Can viewers redeem songs with channel points or bits?',
        a: 'Yes. WolfWave can auto-create a "Request a Song" channel-point reward and accept bit-cheer boosts to jump the queue.',
      },
    ],
  };

  const faqs = slugRoot ? faqByPage[slugRoot] : undefined;
  const faqLd = faqs
    ? {
        '@context': 'https://schema.org',
        '@type': 'FAQPage',
        mainEntity: faqs.map((f) => ({
          '@type': 'Question',
          name: f.q,
          acceptedAnswer: { '@type': 'Answer', text: f.a },
        })),
      }
    : null;

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
      {howToLd && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(howToLd) }}
        />
      )}
      {faqLd && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(faqLd) }}
        />
      )}
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
  const ogTitle = page.data.ogTitle ?? page.data.title;
  const ogDescription = page.data.ogDescription ?? page.data.description;
  const alt = `${ogTitle} — WolfWave for Apple Music on macOS (Twitch, Discord, OBS)`;
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
      title: ogTitle,
      description: ogDescription,
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
      title: ogTitle,
      description: ogDescription,
      images: [ogImage],
    },
  };
}

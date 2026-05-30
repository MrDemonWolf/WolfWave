import { ImageResponse } from "next/og";
import { OgCard, OG_SIZE, OG_CONTENT_TYPE, loadOgFonts } from "./og/_components/og-card";
import { homepageSeo } from "@/lib/site";

// Root social card. Copy lives in `homepageSeo` (lib/site.ts) so this image,
// the Twitter image, and the homepage meta tags can never drift apart.
export const alt = homepageSeo.ogImageAlt;
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;
export const dynamic = "force-static";
export const revalidate = false;

export default async function Image() {
  const fonts = await loadOgFonts();
  return new ImageResponse(
    (
      <OgCard
        eyebrow={homepageSeo.ogEyebrow}
        title={homepageSeo.ogTitle}
        accentWord={homepageSeo.ogAccentWord}
        description={homepageSeo.ogCardDescription}
        chips={[...homepageSeo.ogChips]}
      />
    ),
    {
      ...size,
      fonts: fonts.map((f) => ({ name: f.name, data: f.data, weight: f.weight as 400 | 500 | 700, style: f.style })),
    },
  );
}

import { defineConfig, defineDocs, frontmatterSchema, metaSchema } from 'fumadocs-mdx/config';
import { z } from 'zod';

const extendedFrontmatter = frontmatterSchema.extend({
  keywords: z.array(z.string()).optional(),
  section: z.string().optional(),
  ogChips: z.array(z.string()).optional(),
  ogEyebrow: z.string().optional(),
  ogTitle: z.string().optional(),
  ogDescription: z.string().optional(),
});

// You can customise Zod schemas for frontmatter and `meta.json` here
// see https://fumadocs.dev/docs/mdx/collections
export const docs = defineDocs({
  dir: 'content/docs',
  docs: {
    schema: extendedFrontmatter,
    postprocess: {
      includeProcessedMarkdown: true,
    },
  },
  meta: {
    schema: metaSchema,
  },
});

export default defineConfig({
  mdxOptions: {
    // MDX options
  },
});

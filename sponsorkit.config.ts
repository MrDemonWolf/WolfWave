import { defineConfig, tierPresets } from 'sponsorkit'

export default defineConfig({
  // GitHub login (the account receiving sponsorships)
  github: {
    login: 'nathanialhenniges',
    type: 'user',
  },

  // Output the rendered sponsor list to apps/docs/public/ so the docs site
  // serves it as a static asset at /sponsors.svg
  outputDir: 'apps/docs/public',
  name: 'sponsors',

  formats: ['svg'],

  // Standard tier ladder — adjust as you create real sponsor tiers in GitHub.
  tiers: [
    {
      title: 'Past Sponsors',
      monthlyDollars: -1,
      preset: tierPresets.xs,
    },
    {
      title: 'Backers',
      preset: tierPresets.base,
    },
    {
      title: 'Sponsors',
      monthlyDollars: 10,
      preset: tierPresets.medium,
    },
    {
      title: 'Silver Sponsors',
      monthlyDollars: 50,
      preset: tierPresets.large,
    },
    {
      title: 'Gold Sponsors',
      monthlyDollars: 100,
      preset: tierPresets.xl,
    },
  ],
})

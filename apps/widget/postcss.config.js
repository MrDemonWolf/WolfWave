// PostCSS config for the widget's Tailwind build.
//
// Invoked implicitly by the `tailwindcss` CLI when build.ts runs. Kept as a
// separate file (vs. inline in tailwind.config.ts) so editors / IDEs that load
// the Tailwind language server can pick it up.
export default {
  plugins: {
    tailwindcss: {},
  },
};

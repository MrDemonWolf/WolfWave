import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();
// Normalize optional NEXT_PUBLIC_BASE_PATH to a Next-compatible basePath
const basePath = (() => {
  const envValue = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
  let path = "";
  try {
    path = new URL(envValue).pathname;
  } catch {
    path = envValue;
  }
  // Ensure leading slash and drop trailing slash for Next basePath constraints
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return normalized.endsWith("/") && normalized !== "/"
    ? normalized.slice(0, -1)
    : normalized;
})();

/** @type {import('next').NextConfig} */
const config = {
  output: "export",
  reactStrictMode: true,
  trailingSlash: true,
  basePath: basePath || undefined,
  assetPrefix: basePath ? `${basePath}/` : undefined,
};

export default withMDX(config);

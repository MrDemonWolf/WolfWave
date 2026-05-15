import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();
// Resolve basePath: default to "/wolfwave" (GitHub Pages project path).
// Set NEXT_PUBLIC_BASE_PATH="" to opt out (local dev). Any other value overrides.
const basePath = (() => {
  const envValue = process.env.NEXT_PUBLIC_BASE_PATH;
  if (envValue === undefined) return "/wolfwave";
  if (envValue === "" || envValue === "/") return "";
  let path = envValue;
  try {
    path = new URL(envValue).pathname;
  } catch {
    // not a URL; treat as path string
  }
  if (!path || path === "/") return "";
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return normalized.endsWith("/") ? normalized.slice(0, -1) : normalized;
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

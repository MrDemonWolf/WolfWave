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
  // If empty or root ("/"), don't set a basePath (Next expects empty or a prefix)
  if (!path || path === "/") return "";
  // Ensure leading slash and drop trailing slash
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

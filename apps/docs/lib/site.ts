export const siteUrl = "https://mrdemonwolf.github.io/wolfwave";

export const basePath = (() => {
  const envValue = process.env.NEXT_PUBLIC_BASE_PATH;
  if (envValue === undefined) return "/wolfwave";
  if (envValue === "" || envValue === "/") return "";
  let path = envValue;
  try {
    path = new URL(envValue).pathname;
  } catch {}
  if (!path || path === "/") return "";
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return normalized.endsWith("/") ? normalized.slice(0, -1) : normalized;
})();

export function absoluteUrl(path: string): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  return `${siteUrl}${clean === "/" ? "" : clean}`;
}

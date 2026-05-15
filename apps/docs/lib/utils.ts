export function getAssetPath(path: string): string {
  // Default to "/wolfwave"; explicit "" opts out for local dev.
  const envValue = process.env.NEXT_PUBLIC_BASE_PATH;
  let basePath: string;
  if (envValue === undefined) {
    basePath = "/wolfwave";
  } else if (envValue === "" || envValue === "/") {
    basePath = "";
  } else {
    let parsed = envValue;
    try { parsed = new URL(envValue).pathname; } catch {}
    basePath = !parsed || parsed === "/" ? "" : (parsed.startsWith("/") ? parsed : `/${parsed}`);
  }
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  const normalizedBase = basePath.endsWith("/") ? basePath.slice(0, -1) : basePath;
  return `${normalizedBase}${normalizedPath}`;
}

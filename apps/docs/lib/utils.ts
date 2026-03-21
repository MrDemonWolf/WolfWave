export function getAssetPath(path: string): string {
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH || "";
  // Ensure path starts with /
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  // Remove trailing slash from basePath if present
  const normalizedBase = basePath.endsWith("/") ? basePath.slice(0, -1) : basePath;
  
  return `${normalizedBase}${normalizedPath}`;
}

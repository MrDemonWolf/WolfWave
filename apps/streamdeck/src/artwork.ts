/**
 * Album art for the Now Playing key.
 *
 * Stream Deck's `setImage` takes a data URI, not a URL, so the art has to be
 * fetched and inlined. WolfWave sends an iTunes CDN URL (`mzstatic.com`), which
 * means one network round trip per track — hence the cache, keyed by URL: a
 * track that comes back later, or a repaint from any other state change, must
 * not refetch.
 */

/** Cache of URL -> data URI. Bounded so a long stream cannot grow it forever. */
const cache = new Map<string, string>();

/** Roughly a full stream's worth of distinct tracks. */
const MAX_ENTRIES = 64;

/** How long to wait before giving up on the CDN and drawing the plain key. */
const TIMEOUT_MS = 4_000;

/** Refuse anything larger than a plausible 512px cover. */
const MAX_BYTES = 2 * 1024 * 1024;

/**
 * Fetches album art as a data URI, or returns `undefined` when it cannot.
 *
 * Every failure path is deliberately quiet and returns `undefined`: a key that
 * falls back to its glyph is fine, and a key that throws mid-broadcast is not.
 */
export async function artworkDataURI(url: string): Promise<string | undefined> {
  if (!isHTTPS(url)) return undefined;

  url = thumbnail(url);
  const hit = cache.get(url);
  if (hit !== undefined) return hit;

  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!response.ok) return undefined;

    const type = response.headers.get("content-type") ?? "";
    if (!type.startsWith("image/")) return undefined;

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BYTES) return undefined;

    const dataURI = `data:${type};base64,${Buffer.from(bytes).toString("base64")}`;
    remember(url, dataURI);
    return dataURI;
  } catch {
    // Timeout, DNS, offline, malformed response. All the same to a key.
    return undefined;
  }
}

/** Test seam: drops everything cached. */
export function clearArtworkCache(): void {
  cache.clear();
}

// MARK: - Private helpers

/**
 * HTTPS only, and only from a real host.
 *
 * The URL arrives over the control socket rather than being composed here, so
 * it is treated as input: `file:`, `data:`, and plain `http:` are all refused
 * rather than handed to `fetch`.
 */
function isHTTPS(url: string): boolean {
  try {
    return new URL(url).protocol === "https:";
  } catch {
    return false;
  }
}

/**
 * Rewrites an iTunes artwork URL to a key-sized thumbnail.
 *
 * WolfWave sends a 512x512 URL, which is ~100KB of base64 once inlined. Every
 * marquee frame re-sends the whole image, so at full size that is roughly a
 * megabyte a second over the plugin socket -- enough to get the plugin process
 * terminated, which is exactly what happened. A 72px key never needed more
 * than 144.
 */
function thumbnail(url: string): string {
  return url.replace(/\/(\d+)x(\d+)((?:bb)?\.\w+)$/, "/144x144$3");
}

function remember(url: string, dataURI: string): void {
  // Oldest-first eviction. Map preserves insertion order, and a plain FIFO is
  // right here: the tracks worth keeping are the recent ones.
  if (cache.size >= MAX_ENTRIES) {
    const oldest = cache.keys().next();
    if (!oldest.done) cache.delete(oldest.value);
  }
  cache.set(url, dataURI);
}

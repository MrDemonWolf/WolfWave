/**
 * Album art has to survive a hostile network on a live stream: the key falls
 * back to its glyph, it never throws, and it never refetches a track it has
 * already drawn.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { artworkDataURI, clearArtworkCache } from "../src/artwork.js";

const realFetch = globalThis.fetch;

/** Stubs fetch and counts calls, so caching is observable. */
function stubFetch(handler: (url: string) => Response | Promise<Response>) {
  const calls: string[] = [];
  globalThis.fetch = (async (input: string | URL | Request) => {
    const url = typeof input === "string" ? input : input.toString();
    calls.push(url);
    return handler(url);
  }) as typeof fetch;
  return calls;
}

function imageResponse(bytes = new Uint8Array([1, 2, 3]), type = "image/jpeg") {
  return new Response(bytes, { headers: { "content-type": type } });
}

const URL_A = "https://is1-ssl.mzstatic.com/image/thumb/a/512x512bb.jpg";
const URL_B = "https://is1-ssl.mzstatic.com/image/thumb/b/512x512bb.jpg";
/** What the fetch actually asks for: a key never needs more than 144px. */
const THUMB_A = "https://is1-ssl.mzstatic.com/image/thumb/a/144x144bb.jpg";
const THUMB_B = "https://is1-ssl.mzstatic.com/image/thumb/b/144x144bb.jpg";

afterEach(() => {
  globalThis.fetch = realFetch;
  clearArtworkCache();
});

describe("artworkDataURI", () => {
  test("downscales the request, because every marquee frame re-sends the art", () => {
    // A 512px cover is ~100KB base64; at several frames a second that got the
    // plugin process terminated.
    const calls = stubFetch(() => imageResponse());
    void artworkDataURI(URL_A);
    expect(calls[0]).toBe(THUMB_A);
  });

  test("returns a data URI carrying the served mime type", async () => {
    stubFetch(() => imageResponse());
    const result = await artworkDataURI(URL_A);
    expect(result).toBe(`data:image/jpeg;base64,${btoa("\x01\x02\x03")}`);
  });

  test("caches by URL so a repaint costs no request", async () => {
    const calls = stubFetch(() => imageResponse());

    await artworkDataURI(URL_A);
    await artworkDataURI(URL_A);
    await artworkDataURI(URL_B);

    expect(calls).toEqual([THUMB_A, THUMB_B]);
  });

  test("refuses anything that is not https", async () => {
    const calls = stubFetch(() => imageResponse());

    // The URL arrives over the socket, so it is input, not something we built.
    for (const url of [
      "http://example.com/a.jpg",
      "file:///etc/passwd",
      "data:image/png;base64,AAAA",
      "not a url",
      "",
    ]) {
      expect(await artworkDataURI(url)).toBeUndefined();
    }
    expect(calls).toEqual([]);
  });

  test("gives up on a non-image response", async () => {
    stubFetch(
      () => new Response("<html>nope</html>", {
        headers: { "content-type": "text/html" },
      }),
    );
    expect(await artworkDataURI(URL_A)).toBeUndefined();
  });

  test("gives up on an error status", async () => {
    stubFetch(() => new Response("", { status: 404 }));
    expect(await artworkDataURI(URL_A)).toBeUndefined();
  });

  test("gives up on an empty body", async () => {
    stubFetch(() => imageResponse(new Uint8Array()));
    expect(await artworkDataURI(URL_A)).toBeUndefined();
  });

  test("refuses a body too large to be a cover", async () => {
    stubFetch(() => imageResponse(new Uint8Array(3 * 1024 * 1024)));
    expect(await artworkDataURI(URL_A)).toBeUndefined();
  });

  test("swallows a thrown fetch rather than taking the key down", async () => {
    stubFetch(() => {
      throw new Error("offline");
    });
    expect(await artworkDataURI(URL_A)).toBeUndefined();
  });

  test("does not cache a failure, so the next track change retries", async () => {
    let fail = true;
    const calls = stubFetch(() => {
      if (fail) throw new Error("offline");
      return imageResponse();
    });

    expect(await artworkDataURI(URL_A)).toBeUndefined();
    fail = false;
    expect(await artworkDataURI(URL_A)).toBeDefined();
    expect(calls).toHaveLength(2);
  });
});

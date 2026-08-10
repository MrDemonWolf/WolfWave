"use client";

import Link from "next/link";
import { useEffect } from "react";

/**
 * Static-export 404 page. GitHub Pages serves the exported 404.html at the
 * original URL, so old docs slugs that were merged away can client-redirect
 * to their new homes. The map covers the 2026-08 docs restructure.
 */
const MOVED: Record<string, string> = {
  "/docs/usage": "/docs/features",
  "/docs/getting-started": "/docs/development",
  "/docs/appearance": "/docs/settings",
};

export default function NotFound() {
  useEffect(() => {
    const { pathname, hash } = window.location;
    // basePath is "/wolfwave" in production, "" in dev.
    const base = pathname.startsWith("/wolfwave") ? "/wolfwave" : "";
    const path = pathname.slice(base.length).replace(/\/$/, "");
    const target = MOVED[path];
    if (target) {
      window.location.replace(`${base}${target}/${hash}`);
    }
  }, []);

  return (
    <main
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "0.75rem",
        minHeight: "60vh",
        textAlign: "center",
        padding: "2rem",
      }}
    >
      <h1 style={{ fontSize: "1.5rem", fontWeight: 600 }}>Page not found</h1>
      <p>Some pages moved in a docs cleanup. Looking for one of these?</p>
      <ul style={{ display: "flex", flexDirection: "column", gap: "0.25rem" }}>
        <li>
          <Link href="/docs/features">Features</Link> (was Usage)
        </li>
        <li>
          <Link href="/docs/development">Development</Link> (was Build from Source)
        </li>
        <li>
          <Link href="/docs/settings">Settings</Link> (was Appearance)
        </li>
      </ul>
      <p>
        Or head to the <Link href="/docs">documentation home</Link>.
      </p>
    </main>
  );
}

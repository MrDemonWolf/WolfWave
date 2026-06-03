"use client";

import { useEffect, useState } from "react";
import { ArrowUp } from "lucide-react";

/**
 * Floating "back to top" control for the landing page only (rendered from
 * the home page, not the shared layout). Fades in after the visitor scrolls
 * past the hero and scrolls smoothly to the top, honoring reduced-motion.
 */
export function BackToTop() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    const onScroll = () => setShow(window.scrollY > 700);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const toTop = () => {
    const reduce = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
  };

  return (
    <button
      type="button"
      onClick={toTop}
      aria-label="Back to top"
      className={`ww-to-top${show ? " is-visible" : ""}`}
      tabIndex={show ? 0 : -1}
    >
      <ArrowUp className="w-5 h-5" aria-hidden="true" />
    </button>
  );
}

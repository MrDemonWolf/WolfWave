/**
 * Format a second count as `m:ss`.
 *
 * Single shared implementation for the docs site (landing-page demo widgets
 * and the OBS widget preview page). Clamps negative/NaN input to 0 so a
 * mid-stream elapsed glitch renders as `0:00` instead of `-1:-30`.
 *
 * The native OBS widget (`apps/widget/src/widget.ts`) keeps its own copy by
 * design: it compiles to a self-contained committed artifact and cannot
 * import from the docs package.
 */
export function formatTime(totalSec: number): string {
  const safe = Math.max(0, Math.floor(totalSec)) || 0;
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

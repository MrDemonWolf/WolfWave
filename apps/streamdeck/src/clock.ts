/**
 * The one place the plugin reads wall-clock time.
 *
 * Hold-to-confirm is the difference between clearing a queue and not clearing
 * it, so its timing has to be testable without sleeping in a test. One seam is
 * enough; anything more elaborate would be a scheduler nobody asked for.
 */

/** Milliseconds since the epoch. Swap in a test to control elapsed time. */
export let now: () => number = () => Date.now();

/** Test-only: replaces the clock. Pass nothing to restore the real one. */
export function setClock(clock?: () => number): void {
  now = clock ?? (() => Date.now());
}

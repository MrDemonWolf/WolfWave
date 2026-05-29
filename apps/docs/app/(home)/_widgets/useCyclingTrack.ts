"use client";

import { useEffect, useMemo, useState } from "react";
import { SAMPLE_TRACKS, type SampleTrack } from "./sample-tracks";

/**
 * Demo cadence — how long each sample track is shown before swapping.
 * Real tracks are 3-4 minutes, way too slow for a marketing demo.
 * 7 seconds is short enough to feel alive without being seizure-grade.
 */
const TRACK_DWELL_MS = 7000;

/**
 * Fake-elapsed advances faster than wall-clock so the progress bar
 * visibly fills during the dwell window. We scale so a full TRACK_DWELL_MS
 * roughly equals the full track duration.
 */
const PROGRESS_TICK_MS = 100;

export interface CyclingTrackState {
  track: SampleTrack;
  /** Elapsed seconds for the *current* track (fake). */
  elapsedSec: number;
  /** 0..1 progress fraction for the current track. */
  progress: number;
  /** Whether motion (cycling + progress fill) is active. */
  motionEnabled: boolean;
}

/**
 * Shared timer that cycles through SAMPLE_TRACKS and emits a fake
 * elapsed-time tick. Both the Discord card and the OBS widget consume
 * this so they stay in lockstep visually.
 *
 * Honors `prefers-reduced-motion: reduce` — freezes on track 0 with no
 * progress animation.
 */
export function useCyclingTrack(): CyclingTrackState {
  const [index, setIndex] = useState(0);
  const [elapsedSec, setElapsedSec] = useState(0);
  const [motionEnabled, setMotionEnabled] = useState(true);

  // Detect reduced motion preference once on mount + listen for changes.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const apply = () => setMotionEnabled(!mq.matches);
    apply();
    mq.addEventListener("change", apply);
    return () => mq.removeEventListener("change", apply);
  }, []);

  // Cycle through tracks at the dwell interval.
  useEffect(() => {
    if (!motionEnabled) return;
    const id = window.setInterval(() => {
      setIndex((i) => (i + 1) % SAMPLE_TRACKS.length);
      setElapsedSec(0);
    }, TRACK_DWELL_MS);
    return () => window.clearInterval(id);
  }, [motionEnabled]);

  // Tick the fake elapsed counter. The cycle effect above already resets
  // elapsedSec to 0 each time it bumps the index, so no separate reset is
  // needed — index changes nowhere else.
  const track = SAMPLE_TRACKS[index];
  useEffect(() => {
    if (!motionEnabled) return;
    const increment = (track.durationSec / TRACK_DWELL_MS) * PROGRESS_TICK_MS;
    const id = window.setInterval(() => {
      setElapsedSec((e) => Math.min(track.durationSec, e + increment));
    }, PROGRESS_TICK_MS);
    return () => window.clearInterval(id);
  }, [motionEnabled, track.durationSec]);

  const progress = useMemo(
    () => Math.min(1, elapsedSec / track.durationSec),
    [elapsedSec, track.durationSec],
  );

  return { track, elapsedSec, progress, motionEnabled };
}

"use client";

import { useSyncExternalStore } from "react";
import { SAMPLE_TRACKS, type SampleTrack } from "./sample-tracks";

/**
 * Shared cycling-track store. ONE timer drives every now-playing widget on the
 * page (Discord card, OBS overlay, Twitch chat) so they stay in genuine
 * lockstep — the Twitch bot's !song / !last replies always match the track the
 * Discord card and overlay are currently showing.
 *
 * Demo cadence: linger ~10s per track, advance the progress bar at a slow,
 * believable creep, and seed each track a little way in (never 0:00).
 * Honors prefers-reduced-motion (freezes on the seeded first track).
 */
const DWELL_MS = 10000;
const TICK_MS = 200;
const PLAYBACK_RATE = 1.6; // song-seconds advanced per real second
const START_FRACTIONS = [0.31, 0.47, 0.22, 0.58];

function seededElapsed(i: number): number {
  return Math.round(
    SAMPLE_TRACKS[i].durationSec * START_FRACTIONS[i % START_FRACTIONS.length],
  );
}

let index = 0;
let elapsed = seededElapsed(0);
let motion = true;
let started = false;
let dwellTimer: ReturnType<typeof setInterval> | null = null;
let tickTimer: ReturnType<typeof setInterval> | null = null;

const listeners = new Set<() => void>();

export interface CyclingTrackState {
  track: SampleTrack;
  /** The track that played immediately before the current one. */
  lastTrack: SampleTrack;
  elapsedSec: number;
  progress: number;
  motionEnabled: boolean;
}

function build(): CyclingTrackState {
  const n = SAMPLE_TRACKS.length;
  const track = SAMPLE_TRACKS[index];
  return {
    track,
    lastTrack: SAMPLE_TRACKS[(index - 1 + n) % n],
    elapsedSec: elapsed,
    progress: Math.min(1, elapsed / track.durationSec),
    motionEnabled: motion,
  };
}

let snapshot: CyclingTrackState = build();

function emit() {
  snapshot = build();
  listeners.forEach((l) => l());
}

function start() {
  if (started) return;
  started = true;
  if (typeof window !== "undefined") {
    motion = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
  if (!motion) {
    emit();
    return;
  }
  dwellTimer = setInterval(() => {
    index = (index + 1) % SAMPLE_TRACKS.length;
    elapsed = seededElapsed(index);
    emit();
  }, DWELL_MS);
  tickTimer = setInterval(() => {
    const dur = SAMPLE_TRACKS[index].durationSec;
    elapsed = Math.min(dur, elapsed + PLAYBACK_RATE * (TICK_MS / 1000));
    emit();
  }, TICK_MS);
}

function stop() {
  started = false;
  if (dwellTimer) clearInterval(dwellTimer);
  if (tickTimer) clearInterval(tickTimer);
  dwellTimer = null;
  tickTimer = null;
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  start();
  return () => {
    listeners.delete(cb);
    if (listeners.size === 0) stop();
  };
}

function getSnapshot(): CyclingTrackState {
  return snapshot;
}

/** Shared now-playing state. Every consumer renders the same track. */
export function useCyclingTrack(): CyclingTrackState {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

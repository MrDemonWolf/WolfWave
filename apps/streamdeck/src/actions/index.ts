/**
 * The v3 key set. One class per manifest action.
 *
 * Every UUID here must match an entry in
 * `com.mrdemonwolf.wolfwave.sdPlugin/manifest.json`; the SDK silently ignores a
 * registered action whose UUID isn't in the manifest.
 */

import { action, type KeyAction } from "@elgato/streamdeck";
import { artworkDataURI } from "../artwork.js";
import {
  Palette,
  audienceGate,
  check,
  countKeyImage,
  hold,
  keyImage,
  labelKeyImage,
  note,
  resume,
  trash,
} from "../keyart.js";
import { AUDIENCE_LABELS, type WolfWaveAction } from "../wolfwave/protocol.js";
import type { WolfWaveState } from "../wolfwave/state.js";
import { KeyState, WolfWaveKeyAction } from "./base.js";

const PLUGIN_UUID = "com.mrdemonwolf.wolfwave";

// MARK: - Playback

@action({ UUID: `${PLUGIN_UUID}.playpause` })
export class PlayPauseAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "play_pause";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setTitle(truncate(state.track));
    await key.setState(state.isPlaying ? KeyState.secondary : KeyState.primary);
  }
}

@action({ UUID: `${PLUGIN_UUID}.skip` })
export class SkipAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "skip";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

// MARK: - Queue

/**
 * One key for both hold and resume: which command it sends depends on whether
 * the queue is currently held, read from `queue_state.held`.
 *
 * Reading real state rather than tracking a local toggle matters because hold is
 * changeable from the tray, chat (`!hold`), and Settings — a plugin-local guess
 * inverts the moment hold is used from any of those. The app rebroadcasts
 * `queue_state` on every hold change, so the key follows.
 */
@action({ UUID: `${PLUGIN_UUID}.queuehold` })
export class QueueHoldAction extends WolfWaveKeyAction {
  protected commandFor(state: WolfWaveState): WolfWaveAction {
    return state.queueHeld ? "resume_queue" : "hold_queue";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setImage(
      countKeyImage({
        glyph: state.queueHeld ? resume : hold,
        count: state.queueCount,
        tile: state.queueHeld ? Palette.tile : undefined,
      }),
    );
    await key.setTitle("");
    await key.setState(state.queueHeld ? KeyState.secondary : KeyState.primary);
  }
}

@action({ UUID: `${PLUGIN_UUID}.approvenext` })
export class ApproveNextAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "approve_next";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    // Pending is the whole point of this key. Amber rather than brand blue:
    // this one is asking the streamer to do something, not reporting a state.
    const pending = state.queuePending > 0;
    await key.setImage(
      countKeyImage({
        glyph: check,
        count: state.queuePending,
        tile: pending ? Palette.warning : undefined,
        tint: Palette.dim,
      }),
    );
    await key.setTitle("");
    await key.setState(pending ? KeyState.secondary : KeyState.primary);
  }
}

/**
 * The one key that destroys something with no undo, so it is the one key you
 * have to hold. A stray press here throws away every request in the queue,
 * which on a live stream is a mess of "where did my song go" in chat.
 */
@action({ UUID: `${PLUGIN_UUID}.clearqueue` })
export class ClearQueueAction extends WolfWaveKeyAction {
  /** Long enough to be deliberate, short enough not to feel broken. */
  protected override get holdToConfirmMs(): number {
    return 800;
  }

  protected commandFor(): WolfWaveAction {
    return "clear_queue";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setImage(
      countKeyImage({
        glyph: trash,
        count: state.queueCount,
        tint: Palette.danger,
      }),
    );
    await key.setTitle("");
  }
}

@action({ UUID: `${PLUGIN_UUID}.blockcurrent` })
export class BlockCurrentAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "block_current";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

// MARK: - Integration toggles

@action({ UUID: `${PLUGIN_UUID}.overlaytoggle` })
export class OverlayToggleAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "overlay_toggle";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setTitle("");
    await key.setState(
      state.health.overlay ? KeyState.secondary : KeyState.primary,
    );
  }
}

// MARK: - Chat

@action({ UUID: `${PLUGIN_UUID}.announcesong` })
export class AnnounceSongAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "announce_song";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

/**
 * Rejects the request that is playing and tells chat it went. Distinct from
 * Skip, which advances playback and says nothing — a silent removal reads to
 * the requester like the bot ate their song.
 */
@action({ UUID: `${PLUGIN_UUID}.rejectcurrent` })
export class RejectCurrentAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "reject_current";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

/**
 * Bars the person who requested what is playing. Held, like Clear Queue: it
 * shuts someone out of the queue entirely, and the app has no undo beyond
 * removing the entry in Settings.
 */
@action({ UUID: `${PLUGIN_UUID}.blockrequester` })
export class BlockRequesterAction extends WolfWaveKeyAction {
  protected override get holdToConfirmMs(): number {
    return 800;
  }

  protected commandFor(): WolfWaveAction {
    return "block_requester";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

/**
 * Walks the request gate one step tighter each press and wraps back to open.
 *
 * Renders the audience it reads from the app rather than the one it last sent,
 * so changing the audience in Settings moves the key too.
 */
@action({ UUID: `${PLUGIN_UUID}.cycleaudience` })
export class CycleAudienceAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "cycle_audience";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    const open = state.requestAudience === "everyone";
    await key.setImage(
      labelKeyImage({
        glyph: audienceGate,
        label: AUDIENCE_LABELS[state.requestAudience],
        // Open is the resting state; anything narrower is a gate the streamer
        // put up on purpose and should be able to see at a glance.
        tile: open ? undefined : Palette.tile,
      }),
    );
    await key.setTitle("");
    await key.setState(open ? KeyState.primary : KeyState.secondary);
  }
}

// MARK: - Display

/**
 * Display-only: what is playing, over its album art. Pressing it does nothing
 * rather than firing a command the streamer didn't intend mid-broadcast.
 */
@action({ UUID: `${PLUGIN_UUID}.nowplaying` })
export class NowPlayingAction extends WolfWaveKeyAction {
  protected commandFor(): null {
    return null;
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    // Art is fetched and inlined; a miss just draws the plain key. Deliberately
    // not awaited before the title: the text should land immediately on a track
    // change rather than waiting on a CDN.
    await key.setTitle(truncate(state.track));
    await key.setState(state.isPlaying ? KeyState.secondary : KeyState.primary);

    const art = state.artworkURL
      ? await artworkDataURI(state.artworkURL)
      : undefined;
    if (art) {
      await key.setImage(art);
    } else {
      await key.setImage(keyImage({ glyph: note, titled: true }));
    }
  }
}

// MARK: - Helpers

/** Keeps a track title readable on a 72x72 key. */
function truncate(value: string, max = 18): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1).trimEnd()}…`;
}

/** Every action class, in manifest order. */
export const ACTION_CLASSES = [
  PlayPauseAction,
  SkipAction,
  QueueHoldAction,
  ApproveNextAction,
  ClearQueueAction,
  BlockCurrentAction,
  OverlayToggleAction,
  AnnounceSongAction,
  RejectCurrentAction,
  BlockRequesterAction,
  CycleAudienceAction,
  NowPlayingAction,
] as const;

/**
 * The v3 key set. One class per manifest action.
 *
 * Every UUID here must match an entry in
 * `com.mrdemonwolf.wolfwave.sdPlugin/manifest.json`; the SDK silently ignores a
 * registered action whose UUID isn't in the manifest.
 */

import { action, type KeyAction } from "@elgato/streamdeck";
import {
  Palette,
  check,
  countKeyImage,
  hold,
  resume,
  trash,
} from "../keyart.js";
import type { WolfWaveAction } from "../wolfwave/protocol.js";
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
] as const;

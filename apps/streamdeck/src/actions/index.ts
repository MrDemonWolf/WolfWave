/**
 * The v2 key set. One class per manifest action.
 *
 * Every UUID here must match an entry in
 * `com.mrdemonwolf.wolfwave.sdPlugin/manifest.json`; the SDK silently ignores a
 * registered action whose UUID isn't in the manifest.
 */

import { action, type KeyAction } from "@elgato/streamdeck";
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
    await key.setTitle(state.queueCount > 0 ? String(state.queueCount) : "");
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
    // Pending is the whole point of this key — show it, or nothing.
    await key.setTitle(state.queuePending > 0 ? String(state.queuePending) : "");
    await key.setState(
      state.queuePending > 0 ? KeyState.secondary : KeyState.primary,
    );
  }
}

@action({ UUID: `${PLUGIN_UUID}.clearqueue` })
export class ClearQueueAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "clear_queue";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setTitle(state.queueCount > 0 ? String(state.queueCount) : "");
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

@action({ UUID: `${PLUGIN_UUID}.discordtoggle` })
export class DiscordToggleAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "discord_toggle";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setTitle("");
    await key.setState(
      state.health.discord ? KeyState.secondary : KeyState.primary,
    );
  }
}

@action({ UUID: `${PLUGIN_UUID}.musicsynctoggle` })
export class MusicSyncToggleAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "music_sync_toggle";
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    await key.setTitle("");
    await key.setState(
      state.health.music ? KeyState.secondary : KeyState.primary,
    );
  }
}

@action({ UUID: `${PLUGIN_UUID}.cycletheme` })
export class CycleThemeAction extends WolfWaveKeyAction {
  protected commandFor(): WolfWaveAction {
    return "cycle_theme";
  }

  protected async render(key: KeyAction): Promise<void> {
    await key.setTitle("");
  }
}

// MARK: - Status

/**
 * Display-only key. Pressing it does nothing rather than firing a command the
 * streamer didn't intend mid-broadcast.
 */
@action({ UUID: `${PLUGIN_UUID}.status` })
export class StatusAction extends WolfWaveKeyAction {
  protected commandFor(): null {
    return null;
  }

  protected async render(
    key: KeyAction,
    state: WolfWaveState,
  ): Promise<void> {
    const up = [
      state.health.music ? "Music" : null,
      state.health.twitch ? "Twitch" : null,
      state.health.discord ? "Discord" : null,
    ].filter(Boolean);
    await key.setTitle(up.length > 0 ? up.join("\n") : "No links");
    await key.setState(
      up.length > 0 ? KeyState.secondary : KeyState.primary,
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
  DiscordToggleAction,
  MusicSyncToggleAction,
  CycleThemeAction,
  StatusAction,
] as const;

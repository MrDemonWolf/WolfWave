"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { ChevronLeft, ChevronRight, Gift, Smile, Users } from "lucide-react";
import { SAMPLE_TRACKS, type SampleTrack } from "./sample-tracks";
import { useCyclingTrack } from "./useCyclingTrack";

/**
 * Live recreation of a Twitch "Stream Chat" popout. Messages stream in over
 * time — viewers praise the app, ask pricing, request songs, and run
 * !song / !last — and the WolfWave bot replies with the CURRENT / LAST track
 * pulled from the shared cycling store, so its answers always match what the
 * Discord card and OBS overlay are showing. Dark in both site themes (Twitch
 * chat always is). All usernames/messages invented; song names come from the
 * single source of truth, sample-tracks.ts.
 */

const TW = {
  bg: "#18181b",
  header: "#1f1f23",
  field: "#0e0e10",
  border: "#2a2a2d",
  text: "#efeff1",
  muted: "#adadb8",
  purple: "#9147ff",
};
const BOT = { color: "#3aa0ff", badge: { label: "BOT", bg: "#0a84ff" } };

interface Msg {
  id: number;
  user: string;
  color: string;
  body: ReactNode;
  badge?: { label: string; bg: string };
}
type Line = Omit<Msg, "id">;
interface Ctx {
  cur: SampleTrack;
  last: SampleTrack;
}

const REQUESTS = SAMPLE_TRACKS.map((t) => t.title);

function v(user: string, color: string, body: ReactNode): Line {
  return { user, color, body };
}
function bot(body: ReactNode): Line {
  return { user: "WolfWave", color: BOT.color, badge: BOT.badge, body };
}
function nowPlaying(t: SampleTrack): ReactNode {
  return (
    <>
      Now playing: <b style={{ color: TW.text }}>{t.title}</b> — {t.artist} 🎵
    </>
  );
}

// Scripted, looping. Each step returns the lines to append (a viewer line and
// the bot's reply usually arrive together). Track-specific lines resolve at
// fire time from the live store.
let reqI = 0;
let queueN = 1;
const SCRIPT: ((c: Ctx) => Line[])[] = [
  () => [v("wolf_fan_88", "#ff8c5a", "okay this overlay is actually clean 🔥")],
  ({ cur }) => [v("nightowl", "#c08bff", "!song"), bot(nowPlaying(cur))],
  () => [v("emote_lord", "#2fd6c3", "the song bot just works, no setup??")],
  () => [v("curious_kate", "#5ac8fa", "wait is wolfwave free?")],
  () => [bot("Yep — free & open source. No account, no paywall. 🐺")],
  ({}) => {
    const title = REQUESTS[reqI++ % REQUESTS.length];
    const n = ++queueN;
    return [
      v("dj_pup", "#ffd60a", `!sr ${title}`),
      bot(
        <>
          Added <b style={{ color: TW.text }}>{title}</b> to the queue · #{n}
        </>,
      ),
    ];
  },
  () => [v("lurker_lobo", "#34c759", "running this all stream, zero crashes")],
  ({ last }) => [
    v("retro_raccoon", "#ff6abf", "!last"),
    bot(
      <>
        Last played: <b style={{ color: TW.text }}>{last.title}</b> — {last.artist}
      </>,
    ),
  ],
  () => [v("synthwave_sam", "#2fd6c3", "what mac app is this, i need it")],
  ({ cur }) => [v("howler_99", "#ff8c5a", "!song"), bot(nowPlaying(cur))],
];

function Badge({ label, bg }: { label: string; bg: string }) {
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        height: 16,
        padding: "0 5px",
        marginRight: 6,
        borderRadius: 4,
        background: bg,
        color: "#fff",
        fontSize: 9,
        fontWeight: 700,
        letterSpacing: "0.04em",
        verticalAlign: "middle",
      }}
    >
      {label}
    </span>
  );
}

function ChatLine({ msg }: { msg: Msg }) {
  return (
    <div className="ww-tw-line" style={{ fontSize: 13, lineHeight: 1.5 }}>
      {msg.badge ? <Badge label={msg.badge.label} bg={msg.badge.bg} /> : null}
      <span style={{ color: msg.color, fontWeight: 700 }}>{msg.user}</span>
      <span style={{ color: TW.muted }}>: </span>
      <span style={{ color: TW.text }}>{msg.body}</span>
    </div>
  );
}

export function TwitchChatPreview({
  viewportHeight = 300,
}: { viewportHeight?: number } = {}) {
  const { track, lastTrack, motionEnabled } = useCyclingTrack();

  // Latest track in a ref so the interval closure always reads current values.
  const ctxRef = useRef<Ctx>({ cur: track, last: lastTrack });
  useEffect(() => {
    ctxRef.current = { cur: track, last: lastTrack };
  }, [track, lastTrack]);

  const idRef = useRef(10);
  const stepRef = useRef(0);

  const seed: Msg[] = [
    { id: 1, user: "wolf_fan_88", color: "#ff8c5a", body: "apple music night 🎧" },
    { id: 2, ...bot(nowPlaying(track)) },
    { id: 3, user: "emote_lord", color: "#2fd6c3", body: "this slaps 🔥" },
  ];
  const [msgs, setMsgs] = useState<Msg[]>(seed);

  useEffect(() => {
    if (!motionEnabled) return;
    const id = window.setInterval(() => {
      const lines = SCRIPT[stepRef.current % SCRIPT.length](ctxRef.current);
      stepRef.current += 1;
      setMsgs((prev) =>
        [...prev, ...lines.map((l) => ({ ...l, id: ++idRef.current }))].slice(-14),
      );
    }, 2600);
    return () => window.clearInterval(id);
  }, [motionEnabled]);

  return (
    <div
      role="img"
      aria-label="Live Twitch chat: viewers requesting songs and running !song while the WolfWave bot replies with the current Apple Music track"
      style={{
        width: "100%",
        maxWidth: 380,
        margin: "0 auto",
        display: "flex",
        flexDirection: "column",
        background: TW.bg,
        border: `1px solid ${TW.border}`,
        borderRadius: 14,
        overflow: "hidden",
        boxShadow: "0 10px 28px -18px rgba(0,0,0,0.45)",
        fontFamily:
          "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      }}
    >
      <style>{`
        @keyframes ww-tw-in { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
        .ww-tw-line { animation: ww-tw-in 0.22s ease both; }
        @media (prefers-reduced-motion: reduce) { .ww-tw-line { animation: none; } }
      `}</style>

      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "10px 12px",
          borderBottom: `1px solid ${TW.border}`,
          background: TW.header,
        }}
      >
        <ChevronLeft size={16} color={TW.muted} aria-hidden="true" />
        <span style={{ color: TW.text, fontSize: 13, fontWeight: 700 }}>Stream Chat</span>
        <span style={{ display: "inline-flex", alignItems: "center", gap: 4, color: TW.muted, fontSize: 12 }}>
          <Users size={15} aria-hidden="true" />
          312
        </span>
      </div>

      {/* Gift a sub */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "10px 12px",
          borderBottom: `1px solid ${TW.border}`,
        }}
      >
        <ChevronLeft size={14} color={TW.muted} aria-hidden="true" />
        <span
          style={{
            flex: 1,
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 7,
            padding: "7px 0",
            borderRadius: 4,
            background: TW.purple,
            color: "#fff",
            fontSize: 12.5,
            fontWeight: 700,
          }}
        >
          <Gift size={15} aria-hidden="true" />
          Gift a Subscription
        </span>
        <ChevronRight size={14} color={TW.muted} aria-hidden="true" />
      </div>

      {/* Live message viewport — bottom-anchored, fixed height, scrolls itself */}
      <div
        style={{
          height: viewportHeight,
          display: "flex",
          flexDirection: "column",
          justifyContent: "flex-end",
          gap: 4,
          padding: "10px 12px",
          overflow: "hidden",
        }}
      >
        {msgs.map((m) => (
          <ChatLine key={m.id} msg={m} />
        ))}
      </div>

      {/* Composer */}
      <div style={{ padding: "10px 12px", borderTop: `1px solid ${TW.border}` }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "9px 10px",
            borderRadius: 6,
            background: TW.field,
            border: `1px solid ${TW.border}`,
          }}
        >
          <span style={{ flex: 1, color: TW.muted, fontSize: 12.5 }}>Send a message</span>
          <Smile size={16} color={TW.muted} aria-hidden="true" />
        </div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end", marginTop: 8 }}>
          <span
            style={{
              padding: "6px 16px",
              borderRadius: 4,
              background: TW.purple,
              color: "#fff",
              fontSize: 12.5,
              fontWeight: 700,
            }}
          >
            Chat
          </span>
        </div>
      </div>
    </div>
  );
}

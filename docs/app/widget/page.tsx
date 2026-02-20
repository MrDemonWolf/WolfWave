"use client";

import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import {
  type WidgetConfigData,
  defaultWidgetConfig,
  resolveTheme,
  layoutDimensions,
  preloadAllGoogleFonts,
} from "./themes";

// MARK: - Types

interface NowPlayingData {
  track: string;
  artist: string;
  album: string;
  duration: number;
  elapsed: number;
  isPlaying: boolean;
  artworkURL: string;
}

type ConnectionStatus = "connected" | "connecting" | "disconnected";

// MARK: - Time Helpers

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

// MARK: - Widget Component

function Widget() {
  const searchParams = useSearchParams();
  const port = searchParams.get("port") || "8765";
  const autohide = Number(searchParams.get("duration") || "0");
  const hideAlbumArt = searchParams.has("hideAlbumArt");

  const [nowPlaying, setNowPlaying] = useState<NowPlayingData | null>(null);
  const [status, setStatus] = useState<ConnectionStatus>("disconnected");
  const [visible, setVisible] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [widgetConfig, setWidgetConfig] =
    useState<WidgetConfigData>(defaultWidgetConfig);

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const rafRef = useRef<number | null>(null);
  const hideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const elapsedRef = useRef({ value: 0, timestamp: 0, isPlaying: false });

  const theme = useMemo(() => resolveTheme(widgetConfig), [widgetConfig]);

  useEffect(() => {
    preloadAllGoogleFonts();
  }, []);

  const layout = widgetConfig.layout || "Horizontal";
  const dims = layoutDimensions[layout] ?? layoutDimensions.Horizontal;

  const startProgressLoop = useCallback(() => {
    if (rafRef.current) cancelAnimationFrame(rafRef.current);

    const tick = () => {
      const { value, timestamp, isPlaying } = elapsedRef.current;
      if (isPlaying && timestamp > 0) {
        const delta = (Date.now() - timestamp) / 1000;
        setElapsed(value + delta);
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
  }, []);

  const stopProgressLoop = useCallback(() => {
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  }, []);

  const showWidget = useCallback(() => {
    setVisible(true);
    if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
    if (autohide > 0) {
      hideTimerRef.current = setTimeout(() => {
        setVisible(false);
      }, autohide * 1000);
    }
  }, [autohide]);

  const handleMessage = useCallback(
    (event: MessageEvent) => {
      try {
        const msg = JSON.parse(event.data);

        switch (msg.type) {
          case "now_playing": {
            const data = msg.data as NowPlayingData;
            setNowPlaying(data);
            elapsedRef.current = {
              value: data.elapsed,
              timestamp: Date.now(),
              isPlaying: data.isPlaying,
            };
            setElapsed(data.elapsed);
            if (data.isPlaying) {
              showWidget();
              startProgressLoop();
            }
            break;
          }
          case "progress": {
            const data = msg.data as {
              elapsed: number;
              duration: number;
              isPlaying: boolean;
            };
            elapsedRef.current = {
              value: data.elapsed,
              timestamp: Date.now(),
              isPlaying: data.isPlaying,
            };
            break;
          }
          case "playback_state": {
            const data = msg.data as NowPlayingData;
            setNowPlaying((prev) => (prev ? { ...prev, ...data } : null));
            elapsedRef.current.isPlaying = data.isPlaying;
            if (!data.isPlaying) {
              stopProgressLoop();
              setVisible(false);
            } else {
              showWidget();
              startProgressLoop();
            }
            break;
          }
          case "widget_config": {
            setWidgetConfig(msg.data as WidgetConfigData);
            break;
          }
          case "welcome":
            break;
        }
      } catch {}
    },
    [showWidget, startProgressLoop, stopProgressLoop]
  );

  useEffect(() => {
    let isMounted = true;

    const connect = () => {
      if (!isMounted) return;
      setStatus("connecting");

      const ws = new WebSocket(`ws://localhost:${port}`);
      wsRef.current = ws;

      ws.onopen = () => {
        if (!isMounted) return;
        setStatus("connected");
        console.log(`[WolfWave Widget] Connected to ws://localhost:${port}`);
      };

      ws.onmessage = (event) => {
        if (!isMounted) return;
        handleMessage(event);
      };

      ws.onclose = () => {
        if (!isMounted) return;
        setStatus("disconnected");
        setVisible(false);
        setNowPlaying(null);
        stopProgressLoop();
        console.log("[WolfWave Widget] Disconnected — retrying in 5s");
        wsRef.current = null;
        reconnectRef.current = setTimeout(connect, 5000);
      };

      ws.onerror = () => {};
    };

    connect();

    return () => {
      isMounted = false;
      if (reconnectRef.current) clearTimeout(reconnectRef.current);
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
      stopProgressLoop();
      wsRef.current?.close();
    };
  }, [port, handleMessage, stopProgressLoop]);

  const progress =
    nowPlaying && nowPlaying.duration > 0
      ? Math.min((elapsed / nowPlaying.duration) * 100, 100)
      : 0;

  const remaining =
    nowPlaying && nowPlaying.duration > 0
      ? Math.max(nowPlaying.duration - elapsed, 0)
      : 0;

  // MARK: - Layout Renderers

  const renderHorizontal = () => (
    <div className="relative flex h-full">
      {!hideAlbumArt && (
        <div className="flex-shrink-0 p-[5px]">
          {nowPlaying!.artworkURL ? (
            <img
              src={nowPlaying!.artworkURL}
              alt={`${nowPlaying!.album} artwork`}
              className="w-[90px] h-[90px] rounded-[10px] object-cover"
              crossOrigin="anonymous"
            />
          ) : (
            <div
              className="w-[90px] h-[90px] rounded-[10px] flex items-center justify-center"
              style={{ background: "rgba(255,255,255,0.10)" }}
            >
              <img
                src="/icon.png"
                alt="WolfWave"
                className="w-[50px] h-[50px] opacity-60"
              />
            </div>
          )}
        </div>
      )}

      <div className="flex flex-col flex-1 min-w-0 justify-center px-3 py-2">
        <div className="min-w-0">
          <p
            className="text-lg font-bold leading-tight truncate"
            style={{
              color: theme.textPrimary,
              textShadow: theme.textShadow,
              fontFamily: theme.fontFamily,
            }}
          >
            {nowPlaying!.track}
          </p>
          <p
            className="text-sm font-thin italic truncate"
            style={{
              color: theme.textSecondary,
              textShadow: theme.textShadow,
              fontFamily: theme.fontFamily,
            }}
          >
            {nowPlaying!.artist}
          </p>
        </div>

        <div className="mt-auto">
          <div
            className="h-[4px] w-full rounded-full overflow-hidden"
            style={{ background: theme.progressTrackBg }}
          >
            <div
              className="h-full rounded-full transition-[width] duration-1000 ease-linear"
              style={{
                width: `${progress}%`,
                background: theme.progressFillBg,
              }}
            />
          </div>

          <div className="flex justify-between mt-0.5">
            <span
              className="text-[10px]"
              style={{ color: theme.textMuted, fontFamily: theme.fontFamily }}
            >
              {formatTime(elapsed)}
            </span>
            <span
              className="text-[10px]"
              style={{ color: theme.textMuted, fontFamily: theme.fontFamily }}
            >
              -{formatTime(remaining)}
            </span>
          </div>
        </div>
      </div>
    </div>
  );

  const renderVertical = () => (
    <div className="relative flex flex-col h-full items-center p-2">
      {!hideAlbumArt && (
        <div className="flex-shrink-0">
          {nowPlaying!.artworkURL ? (
            <img
              src={nowPlaying!.artworkURL}
              alt={`${nowPlaying!.album} artwork`}
              className="w-[200px] h-[200px] rounded-[10px] object-cover"
              crossOrigin="anonymous"
            />
          ) : (
            <div
              className="w-[200px] h-[200px] rounded-[10px] flex items-center justify-center"
              style={{ background: "rgba(255,255,255,0.10)" }}
            >
              <img
                src="/icon.png"
                alt="WolfWave"
                className="w-[80px] h-[80px] opacity-60"
              />
            </div>
          )}
        </div>
      )}

      <div className="flex flex-col flex-1 min-w-0 w-full items-center justify-center mt-1">
        <p
          className="text-sm font-bold leading-tight truncate max-w-full text-center"
          style={{
            color: theme.textPrimary,
            textShadow: theme.textShadow,
            fontFamily: theme.fontFamily,
          }}
        >
          {nowPlaying!.track}
        </p>
        <p
          className="text-xs font-thin italic truncate max-w-full text-center"
          style={{
            color: theme.textSecondary,
            textShadow: theme.textShadow,
            fontFamily: theme.fontFamily,
          }}
        >
          {nowPlaying!.artist}
        </p>
      </div>

      <div className="w-full px-1 mt-auto">
        <div
          className="h-[3px] w-full rounded-full overflow-hidden"
          style={{ background: theme.progressTrackBg }}
        >
          <div
            className="h-full rounded-full transition-[width] duration-1000 ease-linear"
            style={{
              width: `${progress}%`,
              background: theme.progressFillBg,
            }}
          />
        </div>
        <div className="flex justify-between mt-0.5">
          <span
            className="text-[9px]"
            style={{ color: theme.textMuted, fontFamily: theme.fontFamily }}
          >
            {formatTime(elapsed)}
          </span>
          <span
            className="text-[9px]"
            style={{ color: theme.textMuted, fontFamily: theme.fontFamily }}
          >
            -{formatTime(remaining)}
          </span>
        </div>
      </div>
    </div>
  );

  const renderCompact = () => (
    <div className="relative flex h-full items-center px-1">
      {!hideAlbumArt && (
        <div className="flex-shrink-0 p-[5px]">
          {nowPlaying!.artworkURL ? (
            <img
              src={nowPlaying!.artworkURL}
              alt={`${nowPlaying!.album} artwork`}
              className="w-[46px] h-[46px] rounded-[8px] object-cover"
              crossOrigin="anonymous"
            />
          ) : (
            <div
              className="w-[46px] h-[46px] rounded-[8px] flex items-center justify-center"
              style={{ background: "rgba(255,255,255,0.10)" }}
            >
              <img
                src="/icon.png"
                alt="WolfWave"
                className="w-[28px] h-[28px] opacity-60"
              />
            </div>
          )}
        </div>
      )}

      <div className="flex-1 min-w-0 px-2">
        <p
          className="text-sm font-medium leading-tight truncate"
          style={{
            color: theme.textPrimary,
            textShadow: theme.textShadow,
            fontFamily: theme.fontFamily,
          }}
        >
          {nowPlaying!.track}
          <span style={{ color: theme.textMuted }}> — </span>
          <span style={{ color: theme.textSecondary }}>
            {nowPlaying!.artist}
          </span>
        </p>
      </div>
    </div>
  );

  const renderLayout = () => {
    switch (layout) {
      case "Vertical":
        return renderVertical();
      case "Compact":
        return renderCompact();
      default:
        return renderHorizontal();
    }
  };

  return (
    <div className="fixed inset-0 flex items-end justify-center p-4 bg-transparent">
      <div
        className={`
          w-full overflow-hidden relative
          transition-all duration-500 ease-in-out
          ${visible && nowPlaying ? "opacity-100 translate-y-0" : "opacity-0 translate-y-4"}
        `}
        style={{
          maxWidth: `${dims.maxWidth}px`,
          height: `${dims.height}px`,
          background: theme.containerBg,
          border: theme.containerBorder,
          boxShadow: theme.containerShadow,
          borderRadius: theme.containerRadius,
          backdropFilter: theme.backdropFilter,
        }}
      >
        {nowPlaying && (
          <>
            {theme.showArtworkBlur && nowPlaying.artworkURL && (
              <div
                className="absolute inset-0 scale-[1.4] blur-[20px] opacity-90 bg-cover bg-center"
                style={{
                  backgroundImage: `url(${nowPlaying.artworkURL})`,
                }}
              />
            )}

            {theme.overlayBg !== "transparent" && (
              <div
                className="absolute inset-0"
                style={{ background: theme.overlayBg }}
              />
            )}

            {renderLayout()}
          </>
        )}
      </div>
    </div>
  );
}

// MARK: - Page Component

export default function WidgetPage() {
  return (
    <div className="bg-transparent min-h-screen">
      <Suspense fallback={null}>
        <Widget />
      </Suspense>
    </div>
  );
}

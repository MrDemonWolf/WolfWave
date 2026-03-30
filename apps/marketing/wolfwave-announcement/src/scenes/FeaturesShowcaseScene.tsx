import React from 'react';
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  interpolateColors,
} from 'remotion';
import { brand, raveColors, raveColor } from '../brand';

// --- Shared styles ---

const mockShadow =
  '0 16px 48px rgba(0,0,0,0.5), 0 0 40px rgba(15,172,237,0.06)';

// --- Discord Rich Presence ---

const DiscordRPC: React.FC<{ frame: number; fps: number }> = ({
  frame,
  fps,
}) => {
  // Slide in from right (frames 0-30)
  const enterSpring = spring({
    fps,
    frame,
    config: { damping: 60, stiffness: 180 },
    durationInFrames: 30,
  });
  const slideX = interpolate(enterSpring, [0, 1], [120, 0]);

  // Exit: fade + slide left (frames 65-80)
  const exitOpacity = interpolate(frame, [65, 80], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const exitX = interpolate(frame, [65, 80], [0, -60], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Animated progress bar (40%→65%)
  const progress = interpolate(frame, [0, 80], [0.4, 0.65], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Neon border glow cycling
  const borderColor = interpolateColors(
    frame,
    [0, 20, 40, 60, 80],
    [brand.cyan, brand.magenta, brand.purple, brand.pink, brand.cyan]
  );

  return (
    <div
      style={{
        position: 'absolute',
        top: '50%',
        left: 200,
        transform: `translateY(-50%) translateX(${slideX + exitX}px) scale(2)`,
        transformOrigin: 'left center',
        opacity: enterSpring * exitOpacity,
      }}
    >
      <div
        style={{
          fontFamily: brand.fontMono,
          fontSize: 12,
          color: brand.textMuted,
          marginBottom: 12,
          letterSpacing: 1,
        }}
      >
        DISCORD STATUS
      </div>
      <div
        style={{
          background: '#2b2d31',
          borderRadius: 14,
          padding: '20px 24px',
          width: 420,
          boxShadow: `${mockShadow}, 0 0 20px ${borderColor}33`,
          border: `1px solid ${borderColor}44`,
        }}
      >
        {/* User header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            marginBottom: 14,
            paddingBottom: 12,
            borderBottom: '1px solid #3f4147',
          }}
        >
          <div
            style={{
              width: 36,
              height: 36,
              borderRadius: 18,
              background: 'linear-gradient(135deg, #5865F2, #EB459E)',
              position: 'relative',
            }}
          >
            {/* Green status dot */}
            <div
              style={{
                position: 'absolute',
                bottom: -1,
                right: -1,
                width: 12,
                height: 12,
                borderRadius: 6,
                backgroundColor: '#23A559',
                border: '3px solid #2b2d31',
              }}
            />
          </div>
          <div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontWeight: 700,
                fontSize: 14,
                color: '#f2f3f5',
              }}
            >
              MrDemonWolf
            </div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontSize: 11,
                color: '#b5bac1',
              }}
            >
              Online
            </div>
          </div>
        </div>

        {/* Activity label */}
        <div
          style={{
            fontFamily: brand.fontDisplay,
            fontWeight: 700,
            fontSize: 11,
            color: '#b5bac1',
            textTransform: 'uppercase',
            letterSpacing: 0.5,
            marginBottom: 10,
          }}
        >
          Listening to Apple Music
        </div>

        {/* Activity content */}
        <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
          {/* Album art */}
          <div
            style={{
              width: 80,
              height: 80,
              borderRadius: 8,
              background: 'linear-gradient(135deg, #E8445A, #FF6B9D, #C850C0)',
              flexShrink: 0,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="36" height="36" viewBox="0 0 36 36" fill="none">
              <circle cx="13" cy="25" r="6" fill="white" opacity="0.9" />
              <line
                x1="19"
                y1="25"
                x2="19"
                y2="8"
                stroke="white"
                strokeWidth="2.5"
              />
              <path d="M19 8 L30 4 L30 14 L19 17" fill="white" opacity="0.9" />
            </svg>
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontWeight: 700,
                fontSize: 16,
                color: '#f2f3f5',
                marginBottom: 3,
              }}
            >
              Kbps Plz
            </div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontSize: 14,
                color: '#b5bac1',
                marginBottom: 3,
              }}
            >
              by DevBowser
            </div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontSize: 13,
                color: '#949ba4',
                marginBottom: 10,
              }}
            >
              on The Vibes
            </div>

            {/* Progress bar */}
            <div
              style={{
                width: '100%',
                height: 4,
                backgroundColor: '#4e5058',
                borderRadius: 2,
                overflow: 'hidden',
                marginBottom: 4,
              }}
            >
              <div
                style={{
                  width: `${progress * 100}%`,
                  height: '100%',
                  backgroundColor: brand.cyan,
                  borderRadius: 2,
                }}
              />
            </div>
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                fontFamily: brand.fontMono,
                fontSize: 10,
                color: '#949ba4',
              }}
            >
              <span>1:37</span>
              <span>4:20</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// --- Twitch Chat Bot ---

const TwitchChat: React.FC<{ frame: number; fps: number }> = ({
  frame,
  fps,
}) => {
  // Slide in from left (frames 0-30 of local)
  const enterSpring = spring({
    fps,
    frame,
    config: { damping: 60, stiffness: 180 },
    durationInFrames: 30,
  });
  const slideX = interpolate(enterSpring, [0, 1], [-120, 0]);

  // Exit: fade (frames 75-90 of local, which is 125-140 global)
  const exitOpacity = interpolate(frame, [75, 90], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Neon border glow cycling
  const borderColor = interpolateColors(
    frame,
    [0, 20, 40, 60, 80],
    [brand.purple, brand.cyan, brand.magenta, brand.lime, brand.purple]
  );

  const messages = [
    { user: 'owo_whats_this', color: '#A78BFA', text: 'this song slaps' },
    { user: 'beans_n_toebeans', color: '#FF6B6B', text: '!song' },
    {
      user: 'wolfbot',
      color: brand.cyan,
      text: 'WolfWave is connected! 🎵',
      isBot: true,
    },
    { user: 'awoo_irl', color: '#34D399', text: 'this song is a banger 🔥' },
    { user: 'not_a_furry_but', color: '#F472B6', text: '!np' },
    {
      user: 'wolfbot',
      color: brand.cyan,
      text: '🎵 Kbps Plz — DevBowser • 1:37 elapsed',
      isBot: true,
    },
  ];

  return (
    <div
      style={{
        position: 'absolute',
        top: '50%',
        right: 200,
        transform: `translateY(-50%) translateX(${slideX}px) scale(2)`,
        transformOrigin: 'right center',
        opacity: enterSpring * exitOpacity,
      }}
    >
      <div
        style={{
          fontFamily: brand.fontMono,
          fontSize: 12,
          color: brand.textMuted,
          marginBottom: 12,
          letterSpacing: 1,
        }}
      >
        TWITCH CHAT
      </div>
      <div
        style={{
          background: '#18181b',
          borderRadius: 14,
          padding: '16px 20px',
          width: 440,
          boxShadow: `${mockShadow}, 0 0 20px ${borderColor}33`,
          border: `1px solid ${borderColor}44`,
        }}
      >
        {/* Twitch header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            marginBottom: 12,
            paddingBottom: 10,
            borderBottom: '1px solid #2f2f35',
          }}
        >
          <svg width="18" height="18" viewBox="0 0 16 16" fill="none">
            <path
              d="M2 0 L0 4 L0 14 L4 14 L4 16 L6 14 L9 14 L14 9 L14 0 Z"
              fill="#9146FF"
            />
            <path
              d="M10 3 L10 8 M7 3 L7 8"
              stroke="white"
              strokeWidth="1.5"
            />
          </svg>
          <span
            style={{
              fontFamily: brand.fontDisplay,
              fontWeight: 700,
              fontSize: 13,
              color: '#efeff1',
              textTransform: 'uppercase',
              letterSpacing: 1,
            }}
          >
            Stream Chat
          </span>
          <div style={{ flex: 1 }} />
          <div
            style={{
              fontFamily: brand.fontMono,
              fontSize: 11,
              color: '#adadb8',
              display: 'flex',
              alignItems: 'center',
              gap: 5,
            }}
          >
            <div
              style={{
                width: 6,
                height: 6,
                borderRadius: 3,
                backgroundColor: '#E91916',
              }}
            />
            42,069 viewers
          </div>
        </div>

        {/* Chat messages — stagger 12 frames apart */}
        {messages.map((msg, i) => {
          const msgDelay = i * 12;
          const msgOpacity = interpolate(frame - msgDelay, [0, 8], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          });
          const msgY = interpolate(frame - msgDelay, [0, 8], [8, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          });
          return (
            <div
              key={i}
              style={{
                opacity: msgOpacity,
                transform: `translateY(${msgY}px)`,
                fontFamily: brand.fontDisplay,
                fontSize: 14,
                color: '#efeff1',
                marginBottom: 7,
                lineHeight: 1.5,
              }}
            >
              <span style={{ fontWeight: 700, color: msg.color }}>
                {msg.isBot ? '🐺 ' : ''}
                {msg.user}
              </span>
              <span style={{ color: '#adadb8' }}>: </span>
              <span>{msg.text}</span>
            </div>
          );
        })}

        {/* Input field */}
        <div
          style={{
            marginTop: 10,
            padding: '8px 12px',
            borderRadius: 6,
            backgroundColor: '#3f3f46',
            fontFamily: brand.fontDisplay,
            fontSize: 13,
            color: '#71717a',
          }}
        >
          Send a message
        </div>
      </div>
    </div>
  );
};

// --- OBS Browser Source ---

const OBSOverlay: React.FC<{ frame: number; fps: number }> = ({
  frame,
  fps,
}) => {
  // Spring up from bottom
  const enterSpring = spring({
    fps,
    frame,
    config: { damping: 60, stiffness: 180 },
    durationInFrames: 30,
  });
  const slideY = interpolate(enterSpring, [0, 1], [80, 0]);

  // Exit: fade + slight scale-down (frames 75-90 local = 185-200 global)
  const exitOpacity = interpolate(frame, [75, 90], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const exitScale = interpolate(frame, [75, 90], [1, 0.95], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Neon border glow cycling
  const borderColor = interpolateColors(
    frame,
    [0, 20, 40, 60, 80],
    [brand.lime, brand.cyan, brand.pink, brand.magenta, brand.lime]
  );

  const barCount = 7;

  return (
    <div
      style={{
        position: 'absolute',
        top: '50%',
        left: '50%',
        transform: `translate(-50%, -50%) translateY(${slideY}px) scale(${exitScale * 2})`,
        opacity: enterSpring * exitOpacity,
      }}
    >
      <div
        style={{
          fontFamily: brand.fontMono,
          fontSize: 12,
          color: brand.textMuted,
          marginBottom: 12,
          letterSpacing: 1,
          textAlign: 'center',
        }}
      >
        STREAM WIDGETS
      </div>

      {/* Fake stream backdrop */}
      <div
        style={{
          width: 700,
          height: 400,
          borderRadius: 16,
          background:
            'linear-gradient(160deg, #0D1B2A 0%, #1B2838 40%, #0D1B2A 100%)',
          position: 'relative',
          boxShadow: `${mockShadow}, 0 0 20px ${borderColor}33`,
          border: `1px solid ${borderColor}44`,
          overflow: 'hidden',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {/* Subtle grid pattern on backdrop */}
        <div
          style={{
            position: 'absolute',
            inset: 0,
            opacity: 0.03,
            backgroundImage: `linear-gradient(${brand.cyan} 1px, transparent 1px), linear-gradient(90deg, ${brand.cyan} 1px, transparent 1px)`,
            backgroundSize: '40px 40px',
          }}
        />

        {/* "LIVE" indicator */}
        <div
          style={{
            position: 'absolute',
            top: 16,
            left: 16,
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '4px 10px',
            borderRadius: 4,
            backgroundColor: '#E91916',
            fontFamily: brand.fontDisplay,
            fontWeight: 700,
            fontSize: 11,
            color: 'white',
            letterSpacing: 1,
          }}
        >
          LIVE
        </div>

        {/* Glassmorphism overlay widget */}
        <div
          style={{
            position: 'absolute',
            bottom: 24,
            left: 24,
            background: 'rgba(9, 21, 51, 0.85)',
            backdropFilter: 'blur(12px)',
            WebkitBackdropFilter: 'blur(12px)',
            border: `1px solid rgba(15, 172, 237, 0.25)`,
            borderRadius: 14,
            padding: '16px 22px',
            display: 'flex',
            alignItems: 'center',
            gap: 16,
          }}
        >
          {/* Small album art */}
          <div
            style={{
              width: 48,
              height: 48,
              borderRadius: 8,
              background:
                'linear-gradient(135deg, #E8445A, #FF6B9D, #C850C0)',
              flexShrink: 0,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="22" height="22" viewBox="0 0 28 28" fill="none">
              <circle cx="10" cy="20" r="5" fill="white" opacity="0.9" />
              <line
                x1="15"
                y1="20"
                x2="15"
                y2="6"
                stroke="white"
                strokeWidth="2"
              />
              <path
                d="M15 6 L24 3 L24 10 L15 13"
                fill="white"
                opacity="0.9"
              />
            </svg>
          </div>

          {/* Track info */}
          <div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontWeight: 700,
                fontSize: 15,
                color: brand.textPrimary,
                marginBottom: 2,
              }}
            >
              Kbps Plz
            </div>
            <div
              style={{
                fontFamily: brand.fontDisplay,
                fontSize: 13,
                color: brand.textMuted,
              }}
            >
              DevBowser • The Vibes
            </div>
          </div>

          {/* Animated multi-color waveform bars */}
          <div
            style={{
              display: 'flex',
              gap: 3,
              alignItems: 'center',
              height: 32,
              marginLeft: 8,
            }}
          >
            {Array.from({ length: barCount }).map((_, i) => {
              const h =
                8 + 20 * Math.abs(Math.sin(frame * 0.12 + i * 1.2));
              return (
                <div
                  key={i}
                  style={{
                    width: 3,
                    height: h,
                    borderRadius: 2,
                    backgroundColor: raveColor(frame, i),
                  }}
                />
              );
            })}
          </div>
        </div>

        {/* Progress line at bottom of backdrop */}
        <div
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 3,
            backgroundColor: 'rgba(255,255,255,0.1)',
          }}
        >
          <div
            style={{
              width: `${interpolate(frame, [0, 90], [30, 55], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })}%`,
              height: '100%',
              backgroundColor: brand.cyan,
            }}
          />
        </div>
      </div>
    </div>
  );
};

// --- Main Scene ---

export const FeaturesShowcaseScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Header "NOW PLAYING. EVERYWHERE." (fades in frames 0-15)
  const headerOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Header color cycles through rave palette
  const headerColor = interpolateColors(
    frame,
    [0, 50, 100, 150, 200],
    [brand.cyan, brand.magenta, brand.purple, brand.pink, brand.cyan]
  );

  // Centered radial glow that follows active mock
  const glowX = interpolate(
    frame,
    [0, 50, 110, 160],
    [35, 35, 65, 50],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }
  );
  const glowY = interpolate(
    frame,
    [0, 50, 110, 160],
    [50, 50, 50, 50],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }
  );

  // Pulsing glow opacity
  const glowPulse = 0.15 + 0.1 * Math.sin(frame * 0.15);

  // Second magenta/purple glow moves independently
  const glow2X = interpolate(
    frame,
    [0, 50, 110, 160],
    [65, 55, 35, 50],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }
  );
  const glow2Pulse = 0.15 + 0.1 * Math.sin(frame * 0.15 + Math.PI);

  return (
    <AbsoluteFill style={{ backgroundColor: brand.navyDeep }}>
      {/* Ambient cyan glow */}
      <div
        style={{
          position: 'absolute',
          top: `${glowY}%`,
          left: `${glowX}%`,
          transform: 'translate(-50%, -50%)',
          width: 800,
          height: 500,
          borderRadius: '50%',
          background: `radial-gradient(ellipse, ${brand.cyanGlow} 0%, transparent 70%)`,
          opacity: glowPulse,
          transition: 'left 0.5s, top 0.5s',
        }}
      />

      {/* Second magenta/purple glow */}
      <div
        style={{
          position: 'absolute',
          top: `${glowY}%`,
          left: `${glow2X}%`,
          transform: 'translate(-50%, -50%)',
          width: 700,
          height: 450,
          borderRadius: '50%',
          background: `radial-gradient(ellipse, ${brand.magentaGlow} 0%, transparent 70%)`,
          opacity: glow2Pulse,
          transition: 'left 0.5s, top 0.5s',
        }}
      />

      {/* Header — color-cycling */}
      <div
        style={{
          position: 'absolute',
          top: 45,
          left: '50%',
          transform: 'translateX(-50%)',
          fontFamily: brand.fontDisplay,
          fontWeight: 700,
          fontSize: 36,
          color: headerColor,
          letterSpacing: 8,
          textTransform: 'uppercase',
          opacity: headerOpacity,
          textShadow: '0 0 20px currentColor',
        }}
      >
        Now Playing. Everywhere.
      </div>

      {/* Discord RPC (frames 0-80) */}
      <DiscordRPC frame={frame} fps={fps} />

      {/* Twitch Chat (frames 50-140) */}
      {frame >= 50 && <TwitchChat frame={frame - 50} fps={fps} />}

      {/* OBS Browser Source (frames 110-200) */}
      {frame >= 110 && <OBSOverlay frame={frame - 110} fps={fps} />}
    </AbsoluteFill>
  );
};

import React from 'react';
import {
  AbsoluteFill,
  Img,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  interpolateColors,
} from 'remotion';
import { brand, raveColors, raveColor } from '../brand';

const WAVEFORM_PATH =
  'M 0 540 Q 120 340 240 540 Q 320 680 400 540 Q 440 440 480 380 Q 520 320 540 340 Q 560 360 580 540 Q 600 680 640 540 Q 720 340 800 540 Q 840 440 880 380 Q 920 320 940 340 Q 960 360 980 540 Q 1060 740 1140 540 Q 1200 380 1260 340 Q 1300 320 1340 380 Q 1380 440 1420 540 Q 1500 740 1580 540 Q 1660 340 1740 540 Q 1820 680 1920 540';

export const IntroTitleScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Grid fade in (frames 0-20) with pulsing beat effect
  const gridBase = interpolate(frame, [0, 20], [0, 0.04], {
    extrapolateRight: 'clamp',
  });
  const gridPulse = 0.02 + 0.04 * Math.abs(Math.sin(frame * 0.15));
  const gridOpacity = Math.max(gridBase, frame > 20 ? gridPulse : gridBase);

  // Waveform SVG path draws left-to-right (frames 0-50)
  const pathProgress = spring({
    fps,
    frame,
    config: { damping: 80, stiffness: 200 },
    durationInFrames: 50,
  });
  const totalLength = 3200;
  const dashOffset = totalLength * (1 - pathProgress);

  // Waveform stroke color cycles through rave palette
  const waveStrokeColor = interpolateColors(
    frame,
    [0, 25, 50, 75, 100],
    [brand.cyan, brand.magenta, brand.purple, brand.lime, brand.cyan]
  );

  // Radial glow — color-shifting between cyan, magenta, purple
  const glowOpacity = interpolate(frame, [5, 30], [0, 0.6], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const glowColor = interpolateColors(
    frame,
    [0, 40, 80, 120],
    [
      'rgba(15, 172, 237, 0.25)',
      'rgba(255, 0, 255, 0.25)',
      'rgba(191, 0, 255, 0.25)',
      'rgba(15, 172, 237, 0.25)',
    ]
  );

  // Second magenta glow — pulses opposite to the first
  const magentaGlowOpacity =
    interpolate(frame, [10, 35], [0, 0.4], {
      extrapolateLeft: 'clamp',
      extrapolateRight: 'clamp',
    }) *
    (0.15 + 0.1 * Math.sin(frame * 0.15 + Math.PI));

  // Logo (frames 15-45): 600x600, white, scales 0.7→1.0
  const logoSpring = spring({
    fps,
    frame: Math.max(0, frame - 15),
    config: { damping: 60, stiffness: 180 },
    durationInFrames: 30,
  });
  const logoScale = interpolate(logoSpring, [0, 1], [0.7, 1]);
  const logoOpacity = interpolate(frame, [15, 35], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // "WolfWave" title (frames 40-65)
  const titleSpring = spring({
    fps,
    frame: Math.max(0, frame - 40),
    config: { damping: 80, stiffness: 200 },
    durationInFrames: 25,
  });
  const titleY = interpolate(titleSpring, [0, 1], [40, 0]);

  // "v1.0.0" (frames 55-75)
  const versionOpacity = interpolate(frame, [55, 75], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Pulsing waveform bars (frames 50+)
  const barsOpacity = interpolate(frame, [50, 65], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Scene exit (frames 100-120): fade out + lift up
  const exitOpacity = interpolate(frame, [100, 120], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const exitLift = interpolate(frame, [100, 120], [0, -30], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const bars = 64;

  return (
    <AbsoluteFill style={{ backgroundColor: brand.navy }}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: exitOpacity,
          transform: `translateY(${exitLift}px)`,
        }}
      >
        {/* Grid */}
        <svg
          width="1920"
          height="1080"
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            opacity: gridOpacity,
          }}
        >
          {Array.from({ length: 25 }).map((_, i) => (
            <line
              key={`v${i}`}
              x1={i * 80}
              y1={0}
              x2={i * 80}
              y2={1080}
              stroke={brand.cyan}
              strokeWidth={1}
            />
          ))}
          {Array.from({ length: 14 }).map((_, i) => (
            <line
              key={`h${i}`}
              x1={0}
              y1={i * 80}
              x2={1920}
              y2={i * 80}
              stroke={brand.cyan}
              strokeWidth={1}
            />
          ))}
        </svg>

        {/* Radial color-shifting glow */}
        <div
          style={{
            position: 'absolute',
            top: '42%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            width: 900,
            height: 500,
            borderRadius: '50%',
            background: `radial-gradient(ellipse, ${glowColor} 0%, transparent 70%)`,
            opacity: glowOpacity,
          }}
        />

        {/* Second magenta glow layer */}
        <div
          style={{
            position: 'absolute',
            top: '45%',
            left: '48%',
            transform: 'translate(-50%, -50%)',
            width: 1100,
            height: 600,
            borderRadius: '50%',
            background: `radial-gradient(ellipse, ${brand.magentaGlow} 0%, transparent 70%)`,
            opacity: magentaGlowOpacity,
          }}
        />

        {/* Waveform — color-cycling stroke */}
        <svg
          width="1920"
          height="1080"
          style={{ position: 'absolute', top: 0, left: 0 }}
        >
          <path
            d={WAVEFORM_PATH}
            fill="none"
            stroke={waveStrokeColor}
            strokeWidth={3}
            strokeDasharray={totalLength}
            strokeDashoffset={dashOffset}
            strokeLinecap="round"
            opacity={0.5}
          />
        </svg>

        {/* Logo — positioned independently so size doesn't push text */}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: `translate(-50%, -60%) scale(${logoScale})`,
            opacity: logoOpacity,
          }}
        >
          <Img
            src={staticFile('logo.svg')}
            style={{
              width: 750,
              height: 750,
              objectFit: 'contain',
            }}
          />
        </div>

        {/* Title + Version — positioned below logo center */}
        <div
          style={{
            position: 'absolute',
            bottom: 100,
            left: '50%',
            transform: 'translateX(-50%)',
            textAlign: 'center',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          {/* "WolfWave" with neon glow */}
          <div
            style={{
              fontFamily: brand.fontDisplay,
              fontWeight: 700,
              fontSize: 120,
              color: brand.textPrimary,
              lineHeight: 1,
              opacity: titleSpring,
              transform: `translateY(${titleY}px)`,
              textShadow: '0 0 20px rgba(15, 172, 237, 0.5)',
            }}
          >
            WolfWave
          </div>

          {/* "v1.0.0" */}
          <div
            style={{
              fontFamily: brand.fontMono,
              fontSize: 36,
              color: brand.cyan,
              marginTop: 20,
              opacity: versionOpacity,
              textShadow: '0 0 20px currentColor',
            }}
          >
            v1.0.0
          </div>
        </div>

        {/* Pulsing multi-color waveform bars at bottom */}
        <div
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            display: 'flex',
            gap: 3,
            alignItems: 'flex-end',
            height: 80,
            padding: '0 0',
            opacity: barsOpacity,
          }}
        >
          {Array.from({ length: bars }).map((_, i) => {
            const height =
              10 + 60 * Math.abs(Math.sin(frame * 0.1 + i * 0.5));
            return (
              <div
                key={i}
                style={{
                  flex: 1,
                  height,
                  borderRadius: 2,
                  backgroundColor: brand.cyan,
                  opacity: 0.7,
                }}
              />
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};

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
import { brand, raveColor } from '../brand';

export const CTAOutroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // "Self-hosted. Open source. Free." springs in (frames 0-20)
  const headlineSpring = spring({
    fps,
    frame,
    config: { damping: 80, stiffness: 200 },
    durationInFrames: 20,
  });
  const headlineY = interpolate(headlineSpring, [0, 1], [40, 0]);

  // GitHub URL fades in (frames 12-25)
  const urlOpacity = interpolate(frame, [12, 25], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Fade to navy (frames 45-60)
  const fadeOut = interpolate(frame, [45, 60], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  // Pulsing glow opacities — two glows alternating
  const cyanGlowOpacity = 0.15 + 0.1 * Math.sin(frame * 0.15);
  const magentaGlowOpacity = 0.15 + 0.1 * Math.sin(frame * 0.15 + Math.PI);

  // "Download today" color cycles
  const downloadColor = interpolateColors(
    frame,
    [0, 15, 30, 45, 60],
    [brand.cyan, brand.magenta, brand.purple, brand.pink, brand.cyan]
  );

  const bars = 64;

  return (
    <AbsoluteFill style={{ backgroundColor: brand.navy }}>
      {/* Cyan ambient glow — pulsing */}
      <div
        style={{
          position: 'absolute',
          top: '40%',
          left: '45%',
          transform: 'translate(-50%, -50%)',
          width: 800,
          height: 400,
          borderRadius: '50%',
          background: `radial-gradient(ellipse, ${brand.cyanGlow} 0%, transparent 70%)`,
          opacity: cyanGlowOpacity,
        }}
      />

      {/* Magenta ambient glow — pulsing opposite */}
      <div
        style={{
          position: 'absolute',
          top: '42%',
          left: '55%',
          transform: 'translate(-50%, -50%)',
          width: 700,
          height: 350,
          borderRadius: '50%',
          background: `radial-gradient(ellipse, ${brand.magentaGlow} 0%, transparent 70%)`,
          opacity: magentaGlowOpacity,
        }}
      />

      {/* Logo — big and centered, offset upward to clear text */}
      <div
        style={{
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          opacity: headlineSpring,
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

      {/* CTA text — positioned below logo independently */}
      <div
        style={{
          position: 'absolute',
          bottom: 80,
          left: '50%',
          transform: `translateX(-50%) translateY(${headlineY}px)`,
          textAlign: 'center',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          opacity: headlineSpring,
        }}
      >
        <div
          style={{
            fontFamily: brand.fontDisplay,
            fontWeight: 700,
            fontSize: 64,
            color: brand.textPrimary,
            lineHeight: 1.2,
            textAlign: 'center',
            marginBottom: 16,
            whiteSpace: 'nowrap',
            textShadow: '0 0 20px rgba(15, 172, 237, 0.3)',
          }}
        >
          Your music. Everywhere. One app.
        </div>
        <div
          style={{
            fontFamily: brand.fontDisplay,
            fontWeight: 700,
            fontSize: 40,
            color: downloadColor,
            letterSpacing: 2,
            marginBottom: 24,
            opacity: urlOpacity,
            textShadow: '0 0 20px currentColor',
          }}
        >
          Download today
        </div>
        <div
          style={{
            fontFamily: brand.fontMono,
            fontSize: 44,
            color: brand.cyan,
            opacity: urlOpacity,
            textShadow: `0 0 30px ${brand.cyanGlow}, 0 0 60px ${brand.cyanGlow}`,
          }}
        >
          mrdwolf.net/wolfwave
        </div>
      </div>

      {/* Full-width multi-color waveform at bottom edge */}
      <div
        style={{
          position: 'absolute',
          bottom: 0,
          left: 0,
          right: 0,
          display: 'flex',
          gap: 3,
          alignItems: 'flex-end',
          justifyContent: 'center',
          height: 60,
          padding: '0 0',
          opacity: headlineSpring * 0.7,
        }}
      >
        {Array.from({ length: bars }).map((_, i) => {
          const height =
            14 + 40 * Math.abs(Math.sin(frame * 0.1 + i * 0.7));
          return (
            <div
              key={i}
              style={{
                flex: 1,
                height,
                borderRadius: 3,
                backgroundColor: brand.cyan,
              }}
            />
          );
        })}
      </div>

      {/* Fade to navy overlay */}
      <AbsoluteFill
        style={{
          backgroundColor: brand.navy,
          opacity: fadeOut,
        }}
      />
    </AbsoluteFill>
  );
};

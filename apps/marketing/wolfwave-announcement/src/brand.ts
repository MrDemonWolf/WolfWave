export const brand = {
  navy: '#091533',
  navyDeep: '#060E20',
  cyan: '#0FACED',
  cyanGlow: 'rgba(15, 172, 237, 0.2)',
  magenta: '#FF00FF',
  purple: '#BF00FF',
  lime: '#39FF14',
  pink: '#FF6EC7',
  magentaGlow: 'rgba(255, 0, 255, 0.2)',
  purpleGlow: 'rgba(191, 0, 255, 0.2)',
  textPrimary: '#E8F0FF',
  textMuted: '#6B7FA3',
  fontDisplay: 'Space Grotesk',
  fontMono: 'JetBrains Mono',
};

export const raveColors = [brand.cyan, brand.magenta, brand.purple, brand.lime, brand.pink];

/** Pick a rave color based on frame and index for cycling effects */
export const raveColor = (frame: number, i: number): string => {
  const idx = Math.floor((frame * 0.05 + i * 0.3) % raveColors.length);
  return raveColors[(idx + raveColors.length) % raveColors.length];
};

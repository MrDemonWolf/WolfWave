import { Series } from 'remotion';
import { loadFont as loadSpaceGrotesk } from '@remotion/google-fonts/SpaceGrotesk';
import { loadFont as loadJetBrainsMono } from '@remotion/google-fonts/JetBrainsMono';
import { IntroTitleScene } from './scenes/IntroTitleScene';
import { FeaturesShowcaseScene } from './scenes/FeaturesShowcaseScene';
import { CTAOutroScene } from './scenes/CTAOutroScene';

loadSpaceGrotesk('normal', { weights: ['700'], subsets: ['latin'] });
loadJetBrainsMono('normal', { weights: ['400'], subsets: ['latin'] });

export const MainVideo: React.FC = () => (
  <Series>
    <Series.Sequence durationInFrames={120}>
      <IntroTitleScene />
    </Series.Sequence>
    <Series.Sequence durationInFrames={210}>
      <FeaturesShowcaseScene />
    </Series.Sequence>
    <Series.Sequence durationInFrames={60}>
      <CTAOutroScene />
    </Series.Sequence>
  </Series>
);

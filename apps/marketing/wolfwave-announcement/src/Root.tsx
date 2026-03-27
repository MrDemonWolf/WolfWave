import React from 'react';
import { Composition } from 'remotion';
import { MainVideo } from './MainVideo';

export const RemotionRoot: React.FC = () => (
  <Composition
    id="WolfWaveV1"
    component={MainVideo}
    durationInFrames={390}
    fps={30}
    width={1920}
    height={1080}
  />
);

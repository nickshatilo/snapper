import { Composition } from "remotion";
import { SnapperDemo } from "./SnapperDemo";

export const Root: React.FC = () => {
  return (
    <Composition
      id="SnapperDemo"
      component={SnapperDemo}
      durationInFrames={192}
      fps={24}
      width={800}
      height={500}
    />
  );
};

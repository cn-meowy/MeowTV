import MeowTVSvgUrl from "@/assets/MeowTV.svg?url";

interface LogoImageProps {
  className?: string;
  style?: React.CSSProperties;
}

/**
 * MeowTV Logo 组件
 * 使用原始 SVG，透明背景，原色彩显示
 * SVG 中的路径自带颜色，背景完全透明
 */
export function LogoImage({ className = "", style }: LogoImageProps) {
  return (
    <img
      src={MeowTVSvgUrl}
      alt="MeowTV"
      className={className}
      style={style}
    />
  );
}

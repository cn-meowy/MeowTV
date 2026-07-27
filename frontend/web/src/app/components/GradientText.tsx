import React from "react";

interface GradientTextProps {
  from: string;
  to: string;
  children: React.ReactNode;
  className?: string;
  as?: keyof React.JSX.IntrinsicElements;
  extraStyle?: React.CSSProperties;
}

export function GradientText({ from, to, children, className, as: Tag = "span", extraStyle }: GradientTextProps) {
  return (
    <Tag
      className={className}
      style={{
        ...extraStyle,
        backgroundImage: `linear-gradient(135deg, ${from}, ${to})`,
        WebkitBackgroundClip: "text",
        WebkitTextFillColor: "transparent",
        backgroundClip: "text",
        display: "inline-block",
      }}
    >
      {children}
    </Tag>
  );
}

import type { ReactNode, SVGProps } from "react";

/**
 * The icon set, drawn for this site. Same stroke weight as the board lattice,
 * so the marks and the hero read as one hand. No icon font ships with the page.
 */

type IconName =
  | "squares"
  | "pawn"
  | "knight"
  | "bishop"
  | "rook"
  | "eye"
  | "cpu"
  | "link"
  | "puzzle"
  | "voice"
  | "graph"
  | "people"
  | "offline"
  | "github"
  | "arrow"
  | "android"
  | "play";

const PATHS: Record<IconName, ReactNode> = {
  squares: (
    <>
      <rect x="3.5" y="3.5" width="17" height="17" rx="1.5" />
      <path d="M12 3.5v17M3.5 12h17" />
      <path d="M3.5 3.5h4.25v4.25H3.5zM12 12h4.25v4.25H12z" />
    </>
  ),
  pawn: (
    <>
      <path d="M6.2 22h11.6l-1.5-2.3H7.7z" />
      <path d="M9.4 19.1c0-2.6.7-4 1.6-5h2c.9 1 1.6 2.4 1.6 5z" />
      <path d="M8.7 14.1h6.6v1.5H8.7z" />
      <circle cx="12" cy="10.6" r="2.6" />
    </>
  ),
  knight: (
    <>
      <path d="M6.6 22h10.8l-1.5-2.3H8.1z" />
      <path d="M8.6 19.4 9.7 13.9 8.2 12.7 6.6 12.1 8.1 10.2 9.9 8.5 10.4 5.7 11.7 8 12.5 6.2 13.3 8.9 15.3 10.9 16.7 14.7 17 19.4Z" />
    </>
  ),
  bishop: (
    <>
      <path d="M6.6 22h10.8l-1.4-2.2H8z" />
      <path d="M9.3 19.1c0-2.3.6-3.7 1.5-4.7h2.4c.9 1 1.5 2.4 1.5 4.7z" />
      <path d="M9.6 14.6c-.4-2.6.5-4.7 2.4-6.2 1.9 1.5 2.8 3.6 2.4 6.2z" />
      <circle cx="12" cy="6.6" r="1.2" />
    </>
  ),
  rook: (
    <>
      <path d="M6.3 22h11.4l-1.5-2.3H7.8z" />
      <path d="M9.2 19.1V11h5.6v8.1z" />
      <path d="M8.1 10.4V6.3h2v1.7h1.1V6.3h1.6v1.7h1.1V6.3h2v4.1z" />
    </>
  ),
  eye: (
    <>
      <path d="M2.8 12S6.4 5.8 12 5.8 21.2 12 21.2 12 17.6 18.2 12 18.2 2.8 12 2.8 12Z" />
      <circle cx="12" cy="12" r="3.1" />
    </>
  ),
  cpu: (
    <>
      <rect x="6.5" y="6.5" width="11" height="11" rx="1.5" />
      <rect x="10" y="10" width="4" height="4" rx="0.6" />
      <path d="M10 3.5v3M14 3.5v3M10 17.5v3M14 17.5v3M3.5 10h3M3.5 14h3M17.5 10h3M17.5 14h3" />
    </>
  ),
  link: (
    <>
      <path d="m7 7.5 10 9-5 4.5v-18l5 4.5-10 9" />
    </>
  ),
  puzzle: (
    <>
      <path d="M4.5 9.5V6a1.5 1.5 0 0 1 1.5-1.5h3.5a2 2 0 1 1 4 0H18A1.5 1.5 0 0 1 19.5 6v3.5a2 2 0 1 0 0 4V18a1.5 1.5 0 0 1-1.5 1.5h-3.5a2 2 0 1 0-4 0H6A1.5 1.5 0 0 1 4.5 18v-3.5a2 2 0 1 0 0-4Z" />
    </>
  ),
  voice: (
    <>
      <rect x="9.25" y="3" width="5.5" height="10" rx="2.75" />
      <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" />
    </>
  ),
  graph: (
    <>
      <path d="M4 20V4M4 20h16" />
      <path d="m7.5 15.5 3.5-4 3 2.4 4.5-6" />
    </>
  ),
  people: (
    <>
      <circle cx="9" cy="8.5" r="3" />
      <path d="M3.5 20a5.5 5.5 0 0 1 11 0" />
      <path d="M15.5 6.2a3 3 0 0 1 0 5.8M16.5 14.6A5.5 5.5 0 0 1 20.5 20" />
    </>
  ),
  offline: (
    <>
      <path d="M3.4 9.2A12 12 0 0 1 8.6 6.4M15.6 6.5a12 12 0 0 1 5 2.7" />
      <path d="M6.9 12.8a7.5 7.5 0 0 1 3.1-1.7M14.2 11.2a7.5 7.5 0 0 1 2.9 1.6" />
      <path d="M10.2 16.2a3.2 3.2 0 0 1 3.6 0" />
      <path d="M12 19.6h.01" />
      <path d="M3.6 3.6 20.4 20.4" />
    </>
  ),
  github: (
    <>
      <path d="M12 2.8a9.2 9.2 0 0 0-2.9 17.9c.5.1.6-.2.6-.5v-1.7c-2.6.6-3.1-1.2-3.1-1.2-.4-1.1-1-1.4-1-1.4-.9-.6 0-.6 0-.6 1 .1 1.5 1 1.5 1 .8 1.4 2.2 1 2.8.8.1-.6.3-1 .6-1.3-2.1-.2-4.3-1-4.3-4.6 0-1 .4-1.9 1-2.5-.1-.3-.4-1.2.1-2.5 0 0 .8-.3 2.6 1a9 9 0 0 1 4.7 0c1.8-1.3 2.6-1 2.6-1 .5 1.3.2 2.2.1 2.5.6.6 1 1.5 1 2.5 0 3.6-2.2 4.4-4.3 4.6.3.3.6.9.6 1.9v2.8c0 .3.2.6.7.5A9.2 9.2 0 0 0 12 2.8Z" />
    </>
  ),
  arrow: (
    <>
      <path d="M4.5 12h15M13.5 6l6 6-6 6" />
    </>
  ),
  android: (
    <>
      <path d="M3.5 10.6h17V18a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 18z" />
      <path d="M3.5 10.6a8.5 8.5 0 0 1 17 0" />
      <path d="M7.4 7.2 5.9 4.7M16.6 7.2l1.5-2.5" />
      <path d="M9.2 8.2h.01M14.8 8.2h.01" />
      <path d="M7.4 19.5v1.6a1.4 1.4 0 0 1-2.8 0v-1.6M19.4 19.5v1.6a1.4 1.4 0 0 1-2.8 0v-1.6" />
    </>
  ),
  play: (
    <>
      <path d="M7.5 4.8v14.4L19.5 12 7.5 4.8Z" />
    </>
  ),
};

/* The piece marks are silhouettes, drawn in the same language as the board
   in the hero. Everything else is a stroked line drawing. */
const SOLID = new Set<IconName>(["pawn", "knight", "bishop", "rook", "play", "github"]);

export function Icon({
  name,
  size = 24,
  ...rest
}: { name: IconName; size?: number } & SVGProps<SVGSVGElement>) {
  const solid = SOLID.has(name);
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill={solid ? "currentColor" : "none"}
      stroke={solid ? "none" : "currentColor"}
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {PATHS[name]}
    </svg>
  );
}

export type { IconName };

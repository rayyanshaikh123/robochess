import type { Metadata, Viewport } from "next";
import { Fraunces, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

/* The type trio from web/design.md. Variable files, so one payload per family
   and no weight ships that the page does not use. */
const fraunces = Fraunces({
  variable: "--font-fraunces",
  subsets: ["latin"],
  display: "swap",
});

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "RoboChess. Chess you can touch, on a board that watches",
  description:
    "RoboChess joins a real chessboard, a camera and a chess engine, so the game never has to move to a screen. The story runs from chaturanga to a board that reads its own position.",
  keywords: [
    "robochess",
    "chaturanga",
    "smart chessboard",
    "electronic chessboard",
    "computer vision chess",
    "stockfish",
    "raspberry pi chess",
    "flutter",
    "fastapi",
  ],
  icons: {
    icon: [
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/app_logo.png", type: "image/png" },
    ],
    apple: "/app_logo.png",
  },
  openGraph: {
    title: "RoboChess. Chess you can touch, on a board that watches",
    description:
      "From an army drawn on the ground to a board that reads its own position. Play in the browser, or bring a real board to it.",
    type: "website",
    // DEPLOY STEP: og:url and og:image need absolute URLs, which only exist
    // once the site has an address. Patch these with the live URL at deploy.
    // url: "https://<live-domain>/",
    // images: ["https://<live-domain>/og.png"],
  },
};

export const viewport: Viewport = {
  themeColor: "#f7f4ec",
  colorScheme: "light",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${fraunces.variable} ${inter.variable} ${jetbrainsMono.variable}`}
    >
      <body>{children}</body>
    </html>
  );
}

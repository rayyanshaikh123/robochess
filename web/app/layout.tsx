import type { Metadata } from "next";
import { Outfit, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const outfit = Outfit({
  variable: "--font-outfit",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
});

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  weight: ["400", "500", "700"],
});

export const metadata: Metadata = {
  title: "RoboChess — The Connected Chess Platform",
  description:
    "Play against AI bots and human opponents, detect moves on a physical board with computer vision, analyze with Stockfish 17, and sync to a robotic smart board. Download the mobile app and join the connected chess platform.",
  keywords: [
    "chess",
    "robochss",
    "flutter",
    "fastapi",
    "stockfish",
    "computer vision",
    "raspberry pi",
    "smart board",
    "ai opponent",
  ],
  icons: {
    icon: "/app_logo.png",
    apple: "/app_logo.png",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${outfit.variable} ${inter.variable} ${jetbrainsMono.variable}`}>
      <head>
        <link
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="min-h-screen flex flex-col overflow-x-hidden bg-[var(--color-background)] text-[var(--color-on-surface)]">
        {children}
      </body>
    </html>
  );
}

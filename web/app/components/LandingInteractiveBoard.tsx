"use client";

import React, { useState } from "react";

type BoardTheme = "wood" | "green" | "birch" | "slate";

interface ThemeConfig {
  id: BoardTheme;
  name: string;
  light: string;
  dark: string;
  border: string;
}

const THEMES: Record<BoardTheme, ThemeConfig> = {
  wood: {
    id: "wood",
    name: "Tournament Wood",
    light: "#F0D9B5",
    dark: "#B58863",
    border: "#3D2415",
  },
  green: {
    id: "green",
    name: "Tournament Green",
    light: "#EEEED2",
    dark: "#769656",
    border: "#1B4332",
  },
  birch: {
    id: "birch",
    name: "Classic Birch",
    light: "#EAD6B8",
    dark: "#A67A53",
    border: "#2C1B10",
  },
  slate: {
    id: "slate",
    name: "Slate Obsidian",
    light: "#CBD5E1",
    dark: "#475569",
    border: "#0F172A",
  },
};

// Initial pieces setup in standard chess starting position
const INITIAL_BOARD: (string | null)[][] = [
  ["♜", "♞", "♝", "♛", "♚", "♝", "♞", "♜"],
  ["♟", "♟", "♟", "♟", "♟", "♟", "♟", "♟"],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, "♙", null, null, null], // e4 move played
  [null, null, null, null, null, "♘", null, null], // Nf3 move played
  ["♙", "♙", "♙", "♙", null, "♙", "♙", "♙"],
  ["♖", "♘", "♗", "♕", "♔", "♗", null, "♖"],
];

export default function LandingInteractiveBoard() {
  const [activeTheme, setActiveTheme] = useState<BoardTheme>("wood");
  const [selectedSquare, setSelectedSquare] = useState<string | null>("e4");
  const theme = THEMES[activeTheme];

  const files = ["a", "b", "c", "d", "e", "f", "g", "h"];

  return (
    <div className="w-full max-w-xl mx-auto flex flex-col items-center">
      {/* ── Top Bar with Opponent Clock & Live Telemetry ── */}
      <div className="w-full bg-[#0E1A14]/90 border border-[#2D6A4F]/40 rounded-t-xl p-3 flex items-center justify-between backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-[#1B4332] border border-[#52B788]/40 flex items-center justify-center font-bold text-white text-sm shadow-sm">
            AI
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-sm text-white font-[var(--font-headline)]">
                RoboBot
              </span>
              <span className="text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded bg-[#2D6A4F]/50 text-[#D8F3DC] border border-[#52B788]/30">
                Level 5 • 1450 ELO
              </span>
            </div>
            <div className="text-[11px] text-[#8FA89B] flex items-center gap-2 font-[var(--font-body)]">
              <span>Captures: ♟♟</span>
              <span className="text-[#52B788] font-bold">+1</span>
            </div>
          </div>
        </div>

        {/* Digital Clock */}
        <div className="bg-[#050A07] border border-[#2D6A4F]/60 rounded-md px-3 py-1.5 text-right shadow-inner">
          <span className="text-[10px] text-[#8FA89B] block tracking-widest font-[var(--font-body)]">
            OPPONENT
          </span>
          <span className="text-base font-bold font-mono text-[#F1F5F3] tracking-wider">
            09:24
          </span>
        </div>
      </div>

      {/* ── Chessboard Container ── */}
      <div
        className="w-full aspect-square border-4 rounded-b-none relative shadow-2xl overflow-hidden select-none transition-colors duration-300"
        style={{ borderColor: theme.border }}
      >
        <div className="grid grid-cols-8 grid-rows-8 w-full h-full">
          {INITIAL_BOARD.map((row, r) =>
            row.map((piece, c) => {
              const isLight = (r + c) % 2 === 0;
              const squareName = `${files[c]}${8 - r}`;
              const isSelected = selectedSquare === squareName;
              const isLastMove = squareName === "e4" || squareName === "e2";
              const isWhitePiece = r >= 4;

              return (
                <div
                  key={squareName}
                  onClick={() => setSelectedSquare(squareName)}
                  className="relative flex items-center justify-center cursor-pointer transition-all duration-150 hover:brightness-105"
                  style={{
                    backgroundColor: isSelected
                      ? "rgba(45, 106, 79, 0.75)"
                      : isLastMove
                      ? "rgba(82, 183, 136, 0.4)"
                      : isLight
                      ? theme.light
                      : theme.dark,
                  }}
                >
                  {/* Rank coordinate on first column */}
                  {c === 0 && (
                    <span
                      className="absolute top-0.5 left-1 text-[9px] font-bold pointer-events-none opacity-80"
                      style={{ color: isLight ? theme.dark : theme.light }}
                    >
                      {8 - r}
                    </span>
                  )}
                  {/* File coordinate on last row */}
                  {r === 7 && (
                    <span
                      className="absolute bottom-0.5 right-1 text-[9px] font-bold pointer-events-none opacity-80"
                      style={{ color: isLight ? theme.dark : theme.light }}
                    >
                      {files[c]}
                    </span>
                  )}

                  {/* Piece Glyph */}
                  {piece && (
                    <span
                      className={`text-2xl sm:text-3xl md:text-4xl drop-shadow-md transition-transform duration-200 ${
                        isSelected ? "scale-110" : ""
                      } ${
                        isWhitePiece
                          ? "text-white [text-shadow:0_1px_3px_rgba(0,0,0,0.8)]"
                          : "text-neutral-900 [text-shadow:0_1px_2px_rgba(255,255,255,0.4)]"
                      }`}
                    >
                      {piece}
                    </span>
                  )}

                  {/* Active target highlight ring */}
                  {squareName === "e5" && (
                    <div className="w-3 h-3 rounded-full bg-[#1B4332]/60" />
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Live Vision Detection Overlay Badge */}
        <div className="absolute top-3 left-3 bg-[#08100C]/90 border border-[#52B788]/60 backdrop-blur-md px-2.5 py-1 rounded-md shadow-lg flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-[#52B788] animate-pulse" />
          <span className="text-[11px] font-mono text-[#D8F3DC] font-medium tracking-wide">
            YOLO: e2e4 (99.4%) • Stockfish +0.48
          </span>
        </div>
      </div>

      {/* ── Bottom Bar with User Player & Clock ── */}
      <div className="w-full bg-[#0E1A14]/90 border border-t-0 border-[#2D6A4F]/40 rounded-b-xl p-3 flex items-center justify-between backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-[#2D6A4F] border border-[#52B788]/40 flex items-center justify-center font-bold text-white text-sm shadow-sm">
            RS
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-sm text-white font-[var(--font-headline)]">
                You (Rayyan)
              </span>
              <span className="text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded bg-[#1B4332] text-[#D8F3DC]">
                WHITE
              </span>
            </div>
            <div className="text-[11px] text-[#8FA89B] flex items-center gap-2 font-[var(--font-body)]">
              <span>Captures: ♙</span>
              <span className="text-white font-mono text-[10px]">1. e4 e5 2. Nf3</span>
            </div>
          </div>
        </div>

        {/* User Clock */}
        <div className="bg-[#101E17] border border-[#52B788]/60 rounded-md px-3 py-1.5 text-right shadow-inner">
          <span className="text-[10px] text-[#52B788] font-bold block tracking-widest font-[var(--font-body)]">
            YOUR TURN
          </span>
          <span className="text-base font-bold font-mono text-white tracking-wider">
            09:52
          </span>
        </div>
      </div>

      {/* ── Theme Switcher Bar ── */}
      <div className="mt-4 flex items-center gap-2 flex-wrap justify-center">
        <span className="text-xs text-[#8FA89B] font-[var(--font-body)] mr-1">
          Board Theme:
        </span>
        {(Object.keys(THEMES) as BoardTheme[]).map((tId) => {
          const t = THEMES[tId];
          const isSelected = activeTheme === tId;
          return (
            <button
              key={tId}
              onClick={() => setActiveTheme(tId)}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold font-[var(--font-headline)] transition-all flex items-center gap-2 border ${
                isSelected
                  ? "bg-[#1B4332] text-white border-[#52B788] shadow-sm shadow-[#1B4332]"
                  : "bg-[#0A140F] text-[#8FA89B] border-[#1B382B] hover:border-[#2D6A4F] hover:text-white"
              }`}
            >
              <span
                className="w-3 h-3 rounded-full border border-black/30"
                style={{ backgroundColor: t.dark }}
              />
              {t.name}
            </button>
          );
        })}
      </div>
    </div>
  );
}

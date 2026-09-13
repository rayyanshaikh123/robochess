import 'package:flutter/material.dart';

// ── Modern Minimal Tech Theme – Colour Tokens ─────────────────────────────────
//
// Modern, sleek, minimal tech aesthetic for RoboChess:
// - Airy modern neutral background (cool slate-50)
// - Crisp pure white card surfaces with subtle modern hairline borders
// - High-contrast modern deep slate typography
// - Modern tech cobalt / electric blue primary accents (clean, high-tech, minimal)
// - The tournament wooden chessboard finish is strictly preserved for the board itself.
//
// This file is the SINGLE source of truth. Every screen imports from here.
// Do NOT redeclare colour constants in individual screen files.

// ── Backgrounds & Surfaces (Modern Minimal Slate & White) ─────────────────────
const kBackground         = Color(0xFFF8FAFC);  // modern minimal slate-50 canvas
const kSurface            = Color(0xFFFFFFFF);  // crisp pure white surface
const kSurfaceContLowest  = Color(0xFFFFFFFF);  // elevated clean white card
const kSurfaceContLow     = Color(0xFFF1F5F9);  // subtle modern slate-100 card / container
const kSurfaceContainer   = Color(0xFFE2E8F0);  // minimal container tray / divider
const kSurfaceContHigh    = Color(0xFFCBD5E1);  // structural slate-300
const kSurfaceContHighest = Color(0xFFF1F5F9);  // chip / badge surface

// ── Primary (Tournament Deep Dark Green – Matching Logo) ──────────────────────
const kPrimary            = Color(0xFF1B4332);  // deep dark tournament pine / forest green (from logo)
const kPrimaryContainer   = Color(0xFF245943);  // rich forest green highlight
const kOnPrimary          = Color(0xFFFFFFFF);  // crisp white on dark green

// ── Secondary (Deep Modern Obsidian / Slate Tech) ────────────────────────────
const kSecondary          = Color(0xFF0F172A);  // deep modern obsidian / slate-900

// ── Text (Crisp Deep Slate Typography) ────────────────────────────────────────
const kOnSurface          = Color(0xFF0F172A);  // crisp deep slate-900 (ultra-readable)
const kOnSurfaceVariant   = Color(0xFF64748B);  // neutral slate-500 (clean, readable subtext)

// ── Outlines & Hairlines ───────────────────────────────────────────────────────
const kOutlineVariant     = Color(0xFFE2E8F0);  // minimal 1px hairline border

// ── Semantic ─────────────────────────────────────────────────────────────────
const kError              = Color(0xFFEF4444);  // modern crimson-500

// ── Tournament Wooden Chessboard Inlay Tokens (Default) ───────────────────────
const kWoodLightSquare    = Color(0xFFF0D9B5);  // warm blonde tournament boxwood / maple
const kWoodDarkSquare     = Color(0xFFB58863);  // rich tournament walnut
const kWoodFrame          = Color(0xFF3D2415);  // carved deep teak border
const kWoodBrassAccent    = Color(0xFFC88A22);  // polished brass corner trim

# RoboChess Web Landing Page — Design Document

## Design Principles

The landing page was completely redesigned to match the Flutter mobile app's
light theme, serve as an app download hub, and communicate the project's value
proposition — all in a clean, light-mode aesthetic with no app screenshots.

## Color System

Colors are defined as CSS custom properties in `globals.css` and map 1:1 to the
Flutter app's `app_colors.dart` tokens:

| Variable                | Hex        | Flutter Token      | Role                           |
| ----------------------- | ---------- | ------------------ | ------------------------------ |
| `--color-background`    | `#F8FAFC`  | `kBackground`      | Canvas (slate-50)              |
| `--color-surface`       | `#FFFFFF`  | `kSurface`         | Crisp white surface            |
| `--color-surface-low`   | `#F1F5F9`  | `kSurfaceContLow`  | Card/tray background (slate-100) |
| `--color-primary`       | `#1B4332`  | `kPrimary`         | Tournament deep forest green   |
| `--color-primary-hover` | `#245943`  | `kPrimaryContainer`| Rich forest highlight          |
| `--color-on-primary`    | `#FFFFFF`  | `kOnPrimary`       | Text on primary                |
| `--color-on-surface`    | `#0F172A`  | `kOnSurface`       | Primary text (deep slate-900)  |
| `--color-on-surface-variant` | `#64748B` | `kOnSurfaceVariant` | Subtext (neutral slate-500) |
| `--color-outline`       | `#E2E8F0`  | `kOutlineVariant`  | Minimal 1px hairline border    |
| `--color-error`         | `#EF4444`  | `kError`           | Semantic error (crimson)       |
| `--color-wood-light`    | `#F0D9B5`  | `kWoodLightSquare` | Tournament boxwood (chess)     |
| `--color-wood-dark`     | `#B58863`  | `kWoodDarkSquare`  | Tournament walnut (chess)      |

## Typography

- **Headlines:** Outfit (Google Font) — bold, tall x-height, used for H1/H2
- **Body:** Inter (Google Font) — readable, neutral, used for paragraphs and UI
- **Mono:** JetBrains Mono — used for code snippets in setup commands

Font variables are declared in `layout.tsx` and consumed via CSS custom properties
`--font-headline` and `--font-body`.

## Layout Structure

```
┌─────────────────────────────────────────────────────┐
│  Top Bar (fixed)                                     │
│  ─ Logo ─── Nav Links ──── Download CTA              │
│                                                    │
│  Hero Section                                        │
│  ── Headline + Subtext + App Store Badges ──         │
│  ── (Right) Lightweight chess board preview ──      │
│                                                    │
│  About Section                                       │
│  ── Project description ──                         │
│  ── Architecture diagram (3-tier) ──                │
│                                                    │
│  Features Section                                   │
│  ── 3-column grid of feature cards ──              │
│                                                    │
│  Download Section                                   │
│  ── App Store badge + Google Play badge ──         │
│  ── Source on GitHub link ──                        │
│                                                    │
│  Tech Stack Section                                 │
│  ── 2x2-2x2 grid of technologies ──                │
│                                                    │
│  Quick Start (Setup Steps)                          │
│  ── Numbered command steps ──                      │
│                                                    │
│  Footer                                             │
│  ── Logo ── Links ── Status ── Copyright ──         │
└─────────────────────────────────────────────────────┘
```

## Key Design Decisions

### Light Mode Only
- Removed the `dark` class from `layout.tsx`
- Removed the dark WebGL shader background (`ShaderCanvas`)
- All surfaces use `var(--color-surface)` (white) or
  `var(--color-surface-low)` (slate-100) with minimal borders
- The page is clean and airy, matching the app's "Modern Minimal Tech" aesthetic

### No App Screenshots
- Replaced the `LandingInteractiveBoard` component (full app preview with
  player bars, clocks, and telemetry badges) with a **lightweight chess board
  preview** — a clean 8x8 grid using the tournament wood palette, with simple
  player labels (You vs RoboBot) and coordinate labels
- The board preview serves as a thematic visual anchor without mimicking the
  mobile app's UI
- App Store and Google Play badges use Material Symbols icons, not screenshots

### App Download Focus
- The "Download" CTA appears in the top bar, hero section, and dedicated download
  section
- Store badges (App Store / Google Play) link to the GitHub repo as placeholders
- The Quick Start section shows real build/run commands from the README:
  `pip install`, `uvicorn`, `flutter run`

### About the Project
- The About section describes RoboChess as a "connected chess platform" combining
  Flutter, FastAPI, computer vision, Stockfish, and optional Pi hardware
- The architecture diagram visualizes the 3-tier stack:
  Client Layer → REST/WebSocket → Server Core → Microservices grid
  (MongoDB, YOLOv8, Stockfish 17, Pi Edge BLE)

### Responsiveness
- Mobile-first with Tailwind's responsive prefixes (`sm:`, `lg:`)
- Container max-width: 1248px (78rem)
- Grid columns collapse from 3 → 2 → 1 on smaller screens
- Top bar nav links collapse to just the Download button on mobile

## Components

### `page.tsx` (Redesigned)
- Complete rewrite — imports `LandingClient` only (no `LandingInteractiveBoard`,
  no `ShaderCanvas`)
- Uses CSS custom properties for all colors
- All sections use `fade-in-up` for scroll-triggered animations
- Includes an inline `InteractiveBoardDemo` component (lightweight board preview)

### `LandingClient.tsx` (Simplified)
- Removed `ShaderCanvas` import and render
- Retains IntersectionObserver setup for `.fade-in-up` animations
- Returns `null` (no background element)

### `layout.tsx` (Updated)
- Removed `dark` class from `<html>`
- Added Material Symbols Outlined font via Google Fonts `<link>`
- Updated metadata description to focus on download + features
- Body uses `bg-[var(--color-background)]` explicitly

### `globals.css` (Rewritten)
- Light-mode color tokens matching the Flutter app
- Utility classes: `.card`, `.btn-primary`, `.download-badge`
- Scroll animation: `.fade-in-up` / `.fade-in-up.visible`
- Font variable declarations in `@theme inline`

## Files Changed

| File | Action |
|------|--------|
| `web/app/globals.css` | Complete rewrite — light theme tokens |
| `web/app/layout.tsx` | Removed `dark` class, added Material Symbols |
| `web/app/page.tsx` | Complete rewrite — clean light-mode design |
| `web/app/LandingClient.tsx` | Simplified — removed shader, kept observer |

## Not Modified
- `web/app/components/ShaderCanvas.tsx` — left in place (unused by new page)
- `web/app/components/LandingInteractiveBoard.tsx` — left in place (unused by new page)
- `web/next.config.ts` — unchanged
- `web/package.json` — unchanged

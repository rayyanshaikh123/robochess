"use client";

import { useEffect, useRef } from "react";
import { drawBoardOfAges } from "../lib/boardArt";

/**
 * The hero: a pinned stage where scroll progress ages one board across five
 * beats. The board is drawn on a canvas, so the journey reverses exactly on
 * the way back up and there is no media file to stall on.
 *
 * The five gate strings below are character for character identical to the
 * media queries in globals.css. If one changes there it changes here.
 */
const GATES = [
  "(max-width: 720px)",
  "(orientation: portrait) and (max-width: 1024px)",
  "(orientation: portrait) and (pointer: coarse)",
  "(orientation: landscape) and (pointer: coarse) and (max-height: 560px)",
  "(prefers-reduced-motion: reduce)",
];

type BandSpec = { a: number; b: number };

/** Band ranges from the design package. Validated by the flick math there. */
const BAND_RANGE: Record<string, BandSpec> = {
  "1": { a: 0.0, b: 0.17 },
  "2": { a: 0.2, b: 0.38 },
  "3": { a: 0.41, b: 0.59 },
  "4": { a: 0.62, b: 0.8 },
  "5": { a: 0.83, b: 1.0 },
};

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);

const smoothstep = (p: number, e0: number, e1: number) => {
  const t = clamp01((p - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
};

/** Seeded, so the scatter is identical on every load. */
const rng = (seed: number) => {
  let s = seed >>> 0;
  return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
};

type Kind = "scatter" | "snap" | "punch" | "weave" | "settle";

/**
 * Split a line into word and character spans, once, with a visually hidden
 * copy of the whole sentence left for screen readers.
 */
function decorate(el: HTMLElement, kind: Kind, rand: () => number) {
  if (el.dataset.split === "1") return;
  const text = (el.textContent ?? "").trim();
  if (!text) return;
  el.dataset.split = "1";

  const sr = document.createElement("span");
  sr.className = "sr-only";
  sr.textContent = text;

  const visual = document.createElement("span");
  visual.setAttribute("aria-hidden", "true");

  const words = text.split(" ");
  const emphasis = (el.dataset.em ?? "")
    .split(",")
    .filter(Boolean)
    .map((n) => Number(n));

  const perWord = kind === "punch" || kind === "settle";
  const totalChars = text.replace(/ /g, "").length;
  let charIndex = 0;

  words.forEach((word, wi) => {
    const w = document.createElement("span");
    w.className = "w";
    if (emphasis.includes(wi)) w.classList.add("em");

    if (perWord) {
      w.style.setProperty("--th", String((wi / Math.max(1, words.length)) * 0.46));
      w.textContent = word;
    } else {
      for (const ch of word) {
        const c = document.createElement("span");
        c.className = "c";
        c.textContent = ch;
        const ordered = charIndex / Math.max(1, totalChars);
        if (kind === "scatter") {
          c.style.setProperty("--th", String(rand() * 0.52));
          c.style.setProperty("--jx", `${(rand() - 0.5) * 54}px`);
          c.style.setProperty("--jy", `${(rand() - 0.5) * 46}px`);
          c.style.setProperty("--jr", `${(rand() - 0.5) * 38}deg`);
        } else if (kind === "snap") {
          c.style.setProperty("--th", String(ordered * 0.5 + rand() * 0.06));
          c.style.setProperty("--jx", `${18 + rand() * 26}px`);
        } else {
          c.style.setProperty("--th", String(ordered * 0.44 + rand() * 0.08));
          c.style.setProperty("--jy", `${(charIndex % 2 ? 1 : -1) * (18 + rand() * 16)}px`);
        }
        w.appendChild(c);
        charIndex++;
      }
    }

    visual.appendChild(w);
    if (wi < words.length - 1) visual.appendChild(document.createTextNode(" "));
  });

  el.textContent = "";
  el.appendChild(sr);
  el.appendChild(visual);
}

export default function HeroScrub() {
  const heroRef = useRef<HTMLElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const bandsRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const hero = heroRef.current;
    const stage = stageRef.current;
    const bandsEl = bandsRef.current;
    const canvas = canvasRef.current;
    if (!hero || !stage || !bandsEl || !canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) {
      // Complete without the drawn hero: the stage is already the composed
      // still, so leaving it alone is the whole fallback.
      return;
    }

    // Hold the hero for a frame while the mode is decided, so the visitor never
    // watches it flip from the still layout into the armed one.
    stage.classList.add("booting");

    const bands = Array.from(bandsEl.querySelectorAll<HTMLElement>(".band"));
    const cache = new WeakMap<HTMLElement, { op: number; k: number; hidden: boolean }>();
    bands.forEach((b) => cache.set(b, { op: -1, k: -1, hidden: false }));

    // One seeded generator for the whole hero, so every load splits the same way.
    const rand = rng(0x10ca1);
    bands.forEach((band) => {
      const kind = (band.dataset.entrance ?? "scatter") as Kind;
      band.querySelectorAll<HTMLElement>("[data-split]").forEach((line) => decorate(line, kind, rand));
    });

    let width = 0;
    let height = 0;
    let dpr = 1;
    let scrubOn = false;
    let onScreen = true;
    let rafId: number | null = null;
    let lastTick = 0;
    let lastPaint = 0;
    let target = 0;
    let shown = 0;
    let loadK = 0;
    let loadStart = 0;
    const started = performance.now();

    const isStatic = () => GATES.some((q) => matchMedia(q).matches);

    function sizeCanvas() {
      const c = canvas as HTMLCanvasElement;
      const rect = c.getBoundingClientRect();
      dpr = Math.min(2, window.devicePixelRatio || 1);
      width = Math.max(1, Math.round(rect.width));
      height = Math.max(1, Math.round(rect.height));
      c.width = Math.round(width * dpr);
      c.height = Math.round(height * dpr);
      ctx?.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function paintBoard(p: number, now: number) {
      if (!ctx) return;
      drawBoardOfAges(ctx, {
        width,
        height,
        progress: p,
        time: (now - started) / 1000,
        compact: !stage!.classList.contains("scrubbing"),
      });
    }

    function heroProgress() {
      const range = hero!.offsetHeight - window.innerHeight;
      if (range <= 0) return 1;
      return clamp01(-hero!.getBoundingClientRect().top / range);
    }

    /** Delta-gated: nothing touches the DOM unless the value actually moved. */
    function updateBands(p: number) {
      for (const band of bands) {
        const id = band.dataset.band ?? "1";
        const { a, b } = BAND_RANGE[id];
        const f = Math.min(0.025, (b - a) / 3);
        const inEase = id === "1" ? 1 : smoothstep(p, a, a + f);
        const outEase = id === "5" ? 1 : 1 - smoothstep(p, b - f, b);
        const op = inEase * outEase;

        const ramp = Number(band.dataset.ramp ?? 0) || Math.min(0.025, (b - a) * 0.35);
        let k = clamp01((p - a) / ramp);
        // Band one assembles once on load, then hands over to the scroll.
        if (id === "1") k = Math.max(k, loadK);

        const state = cache.get(band)!;
        if (Math.abs(op - state.op) > 0.004) {
          state.op = op;
          band.style.opacity = op.toFixed(3);
          const hidden = op < 0.02;
          if (hidden !== state.hidden) {
            state.hidden = hidden;
            band.toggleAttribute("inert", hidden);
          }
        }
        if (Math.abs(k - state.k) > 0.008) {
          state.k = k;
          band.style.setProperty("--k", k.toFixed(3));
        }
      }
    }

    function tick(now: number) {
      const dt = Math.min(100, now - (lastTick || now));
      lastTick = now;

      if (loadK < 1) {
        if (!loadStart) loadStart = now;
        loadK = clamp01((now - loadStart) / 900);
      }

      const k = 0.16;
      shown += (target - shown) * (1 - Math.pow(1 - k, dt / 16.667));
      const settled = Math.abs(target - shown) < 0.0005 && loadK >= 1;
      if (settled) shown = target;

      // Converged frames are ambient only, so they run at about 30fps.
      if (!settled || now - lastPaint > 33) {
        lastPaint = now;
        paintBoard(shown, now);
        updateBands(shown);
      }

      if (!onScreen || document.hidden) {
        rafId = null;
        lastTick = 0;
        return;
      }
      rafId = requestAnimationFrame(tick);
    }

    function kick() {
      if (rafId === null && onScreen && !document.hidden) {
        lastTick = 0;
        rafId = requestAnimationFrame(tick);
      }
    }

    function onScroll() {
      target = heroProgress();
      stage!.classList.toggle("past-cue", target > 0.03);
      kick();
    }

    function enableScrub() {
      if (scrubOn) return;
      scrubOn = true;
      hero!.classList.add("scrubbing");
      stage!.classList.add("scrubbing");
      bandsEl!.classList.add("armed");
      bands.forEach((b) => cache.set(b, { op: -1, k: -1, hidden: false }));
      loadK = 0;
      loadStart = 0;
      window.addEventListener("scroll", onScroll, { passive: true });
      sizeCanvas();
      target = heroProgress();
      shown = target;
      updateBands(shown);
      // Sync everything to where the page already is. A reload part way down
      // the hero would otherwise keep the scroll cue and a stale frame until
      // the visitor moved.
      onScroll();
    }

    function disableScrub() {
      window.removeEventListener("scroll", onScroll);
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
      scrubOn = false;
      hero!.classList.remove("scrubbing");
      stage!.classList.remove("scrubbing");
      bandsEl!.classList.remove("armed");
      bands.forEach((band) => {
        band.style.removeProperty("opacity");
        band.style.setProperty("--k", "1");
        band.removeAttribute("inert");
        cache.set(band, { op: -1, k: 1, hidden: false });
      });
      sizeCanvas();
      paintBoard(1, performance.now());
    }

    function applyHeroMode() {
      if (isStatic()) disableScrub();
      else enableScrub();
    }

    const queries = GATES.map((q) => matchMedia(q));
    queries.forEach((q) => q.addEventListener("change", applyHeroMode));

    const io = new IntersectionObserver(
      (entries) => {
        onScreen = entries[0]?.isIntersecting ?? true;
        if (onScreen && scrubOn) kick();
      },
      { threshold: 0 },
    );
    io.observe(stage);

    const ro = new ResizeObserver(() => {
      sizeCanvas();
      if (scrubOn) {
        target = heroProgress();
        kick();
      } else {
        paintBoard(1, performance.now());
      }
    });
    ro.observe(stage);

    const onVisible = () => {
      if (!document.hidden && scrubOn) kick();
    };
    document.addEventListener("visibilitychange", onVisible);

    applyHeroMode();
    requestAnimationFrame(() => requestAnimationFrame(() => stage.classList.remove("booting")));

    return () => {
      queries.forEach((q) => q.removeEventListener("change", applyHeroMode));
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("scroll", onScroll);
      io.disconnect();
      ro.disconnect();
      if (rafId !== null) cancelAnimationFrame(rafId);
    };
  }, []);

  return (
    <section className="hero" ref={heroRef} aria-label="From chaturanga to a board that sees">
      <div className="stage" ref={stageRef}>
        <canvas className="board-canvas" ref={canvasRef} aria-hidden="true" />
        <div className="veil" aria-hidden="true" />

        <div className="bands" ref={bandsRef}>
          <div className="band" data-band="1" data-entrance="scatter">
            <p className="kicker band-kicker" data-split="">
              6th century, India
            </p>
            <p className="band-title" data-split="">
              It started as an army.
            </p>
            <p className="band-sub">
              Chaturanga: four limbs, sixty four squares, a grid drawn on the ground.
            </p>
          </div>

          <div className="band" data-band="2" data-entrance="snap">
            <p className="kicker band-kicker" data-split="">
              Persia, then everywhere
            </p>
            <p className="band-title" data-split="">
              The grid learned to travel.
            </p>
            <p className="band-sub">
              Shatranj carried the game west. The pieces took a new name in every language they
              passed through.
            </p>
          </div>

          <div className="band" data-band="3" data-entrance="punch">
            <p className="kicker band-kicker" data-split="">
              Europe, around 1475
            </p>
            <p className="band-title" data-split="" data-em="5">
              Then the queen was set free.
            </p>
            <p className="band-sub">
              One rule change turned the slowest piece into the strongest, and the modern game was
              born.
            </p>
          </div>

          <div className="band" data-band="4" data-entrance="weave">
            <p className="kicker band-kicker" data-split="">
              Today
            </p>
            <p className="band-title" data-split="">
              Now the board can see.
            </p>
            <p className="band-sub">
              A camera reads the real pieces. The move appears in the app on its own.
            </p>
          </div>

          <div className="band" data-band="5" data-entrance="settle">
            <h1 className="band-title" data-split="">
              Chess you can touch, on a board that watches.
            </h1>
            <p className="band-sub stage-2">
              RoboChess joins a real chessboard, a camera and a chess engine, so the game never has
              to move to a screen.
            </p>
            <div className="band-actions stage-3">
              <a className="btn btn-solid" href="/app/">
                Open the board
              </a>
              <a className="btn btn-quiet" href="#pipeline">
                See how it works
              </a>
            </div>
          </div>
        </div>

        <div className="stage-furniture" aria-hidden="true">
          <span className="chip">
            <span className="live-dot" /> start position
          </span>
          <span className="chip">64 squares</span>
          <span className="chip">white to move</span>
        </div>

        <div className="scroll-cue" aria-hidden="true">
          <span />
          scroll
        </div>
      </div>
    </section>
  );
}

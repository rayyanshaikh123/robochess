"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { CSSProperties, ReactNode } from "react";

/**
 * The app tour: one phone body held at the centre of the stage, and the six
 * screens riding an arc behind it. Scrolling turns the arc, so each screen
 * swings in, lands inside the phone, and swings out again. Everything off the
 * centre is blurred and scaled back, so the eye only ever has one thing to read.
 *
 * Screenshots live in web/public/screens/ under the file names below. A tab
 * whose shot is missing keeps its frame and says so, rather than showing a
 * broken image.
 */
const SCREENS = [
  {
    file: "home.jpeg",
    tab: "Home",
    caption: "Your record, the board's status, and one button into the next game.",
  },
  {
    file: "play_game.jpeg",
    tab: "Play",
    caption: "A live game against RoboBot, with both clocks, the move list, and a voice button for when your hands are on the pieces.",
  },
  {
    file: "settings.jpeg",
    tab: "Settings",
    caption: "Pick the opponent, the bot's rating, your colour, the clock, and whether the game runs on glass or on wood.",
  },
  {
    file: "analysis.jpeg",
    tab: "Analysis",
    caption: "Step through a finished game move by move, with the engine's number on every position and the swing drawn underneath.",
  },
  {
    file: "learn.jpeg",
    tab: "Learn",
    caption: "A curriculum that keeps your rank and your progress, with the next lesson already queued.",
  },
  {
    file: "connect.jpeg",
    tab: "Connect",
    caption: "Link a physical board, watch it report in, and start the match on the wood.",
  },
];

/** Scroll distance handed to each step of the arc. */
const STEP_VH = 52;

/** The same gate strings the hero uses: these viewports get the plain carousel. */
const GATES = [
  "(max-width: 720px)",
  "(orientation: portrait) and (max-width: 1024px)",
  "(orientation: portrait) and (pointer: coarse)",
  "(orientation: landscape) and (pointer: coarse) and (max-height: 560px)",
  "(prefers-reduced-motion: reduce)",
];

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

const smoothstep = (v: number, e0: number, e1: number) => {
  const t = clamp((v - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
};

export default function AppTour({ footer }: { footer?: ReactNode }) {
  const trackRef = useRef<HTMLDivElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const arcRef = useRef<HTMLDivElement | null>(null);
  const [active, setActive] = useState(0);
  const [plain, setPlain] = useState(false);
  const [missing, setMissing] = useState<Record<string, boolean>>({});
  const activeRef = useRef(0);

  const markMissing = useCallback((file: string) => {
    setMissing((m) => (m[file] ? m : { ...m, [file]: true }));
  }, []);

  /** Manual controls move the page, so scroll stays the single source of truth. */
  const goTo = useCallback((index: number) => {
    const track = trackRef.current;
    const next = clamp(index, 0, SCREENS.length - 1);
    if (!track || plain) {
      setActive(next);
      activeRef.current = next;
      return;
    }
    const range = track.offsetHeight - window.innerHeight;
    const top = track.offsetTop + (range * next) / (SCREENS.length - 1);
    window.scrollTo({ top, behavior: "smooth" });
  }, [plain]);

  useEffect(() => {
    const track = trackRef.current;
    const stage = stageRef.current;
    const arc = arcRef.current;
    if (!track || !stage || !arc) return;

    const cards = Array.from(arc.querySelectorAll<HTMLElement>(".arc-card"));
    const queries = GATES.map((q) => matchMedia(q));

    let raf: number | null = null;
    let onScreen = false;
    let target = 0;
    let shown = 0;
    let lastTick = 0;
    let lastWritten = -1;
    let lastEnd = -1;
    let armed = false;

    const progress = () => {
      const range = track.offsetHeight - window.innerHeight;
      if (range <= 0) return 0;
      return clamp(-track.getBoundingClientRect().top / range, 0, 1);
    };

    /** Lay every card on the arc from one floating index. */
    const layout = (f: number) => {
      if (Math.abs(f - lastWritten) < 0.002) return;
      lastWritten = f;

      const width = stage.clientWidth;
      const radius = Math.min(width * 0.44, 660);
      // A shallow arc on purpose: a deep one swings the outer cards down over
      // the caption, and the caption is the thing you are meant to be reading.
      const depth = Math.min(width * 0.09, 120);

      const ring = SCREENS.length;
      cards.forEach((card, i) => {
        // Wrap the offset around the ring so both sides of the phone always
        // carry screens. The seam sits out past the fade, so it never shows.
        let off = i - f;
        off = (((off + ring / 2) % ring) + ring) % ring - ring / 2;
        const away = Math.abs(off);
        const angle = off * 0.72;
        const x = Math.sin(angle) * radius;
        const y = (1 - Math.cos(angle)) * depth;
        const scale = Math.max(0.42, 1 - away * 0.15);
        // It fades out as it enters the phone, because the phone is showing it.
        const enter = smoothstep(away, 0.12, 0.62);
        const leave = 1 - smoothstep(away, 1.8, 2.7);
        card.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0) scale(${scale.toFixed(3)})`;
        card.style.opacity = (enter * leave).toFixed(3);
        card.style.filter = `blur(${Math.min(10, 1.6 + away * 3.4).toFixed(1)}px)`;
        card.style.zIndex = String(20 - Math.round(away * 4));
      });

      // The download lands as the payoff of the last screen, not after it.
      const last = SCREENS.length - 1;
      const end = smoothstep(f, last - 1.7, last - 1.05);
      if (Math.abs(end - lastEnd) > 0.01) {
        lastEnd = end;
        stage.style.setProperty("--end", end.toFixed(3));
        stage.classList.toggle("is-end", end > 0.6);
      }

      const next = Math.round(clamp(f, 0, SCREENS.length - 1));
      if (next !== activeRef.current) {
        activeRef.current = next;
        setActive(next);
      }
    };

    const tick = (now: number) => {
      const dt = Math.min(100, now - (lastTick || now));
      lastTick = now;
      shown += (target - shown) * (1 - Math.pow(1 - 0.18, dt / 16.667));
      const settled = Math.abs(target - shown) < 0.0004;
      if (settled) shown = target;
      layout(shown * (SCREENS.length - 1));
      if (settled || !onScreen || document.hidden) {
        raf = null;
        lastTick = 0;
        return;
      }
      raf = requestAnimationFrame(tick);
    };

    const kick = () => {
      if (raf === null && onScreen && !document.hidden) {
        lastTick = 0;
        raf = requestAnimationFrame(tick);
      }
    };

    const onScroll = () => {
      target = progress();
      kick();
    };

    const disarm = () => {
      if (!armed) return;
      armed = false;
      window.removeEventListener("scroll", onScroll);
      if (raf !== null) {
        cancelAnimationFrame(raf);
        raf = null;
      }
      cards.forEach((card) => {
        card.style.cssText = "";
      });
      stage.style.removeProperty("--end");
      stage.classList.remove("is-end");
    };

    const arm = () => {
      if (armed) return;
      armed = true;
      window.addEventListener("scroll", onScroll, { passive: true });
      lastWritten = -1;
      lastEnd = -1;
      target = progress();
      shown = target;
      layout(shown * (SCREENS.length - 1));
      kick();
    };

    const applyMode = () => {
      const gated = queries.some((q) => q.matches);
      setPlain(gated);
      if (gated) disarm();
      else arm();
    };

    const io = new IntersectionObserver(
      (entries) => {
        onScreen = entries[0]?.isIntersecting ?? false;
        if (onScreen) kick();
      },
      { threshold: 0 },
    );
    io.observe(stage);

    const ro = new ResizeObserver(() => {
      lastWritten = -1;
      if (armed) {
        target = progress();
        kick();
      }
    });
    ro.observe(stage);

    const onVisible = () => { if (!document.hidden) kick(); };
    document.addEventListener("visibilitychange", onVisible);
    queries.forEach((q) => q.addEventListener("change", applyMode));
    applyMode();

    return () => {
      queries.forEach((q) => q.removeEventListener("change", applyMode));
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("scroll", onScroll);
      io.disconnect();
      ro.disconnect();
      if (raf !== null) cancelAnimationFrame(raf);
    };
  }, []);

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); goTo(active + 1); }
    if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); goTo(active - 1); }
  };

  const shot = (screen: (typeof SCREENS)[number], small = false) =>
    missing[screen.file] ? (
      <span className="tour-awaiting">
        <span className="tour-awaiting-tab">{screen.tab}</span>
        {!small && <span className="tour-awaiting-note">screenshot not added yet</span>}
      </span>
    ) : (
      /* eslint-disable-next-line @next/next/no-img-element */
      <img
        src={`/screens/${screen.file}`}
        alt={small ? "" : `The ${screen.tab} tab of the RoboChess app`}
        aria-hidden={small || undefined}
        loading="lazy"
        decoding="async"
        onError={() => markMissing(screen.file)}
      />
    );

  return (
    <div className={`tour${plain ? " is-plain" : ""}`}>
      <div
        className="tour-track"
        ref={trackRef}
        style={{ "--steps": SCREENS.length - 1, "--step-vh": `${STEP_VH}vh` } as CSSProperties}
      >
        <div className="tour-stage" ref={stageRef}>
          <div className="tour-arc" ref={arcRef} aria-hidden="true">
            {SCREENS.map((screen) => (
              <div className="arc-card" key={screen.file}>
                {shot(screen, true)}
              </div>
            ))}
          </div>

          <div className="phone">
            <span className="phone-island" aria-hidden="true" />
            <span className="phone-btn phone-btn-mute" aria-hidden="true" />
            <span className="phone-btn phone-btn-vol" aria-hidden="true" />
            <span className="phone-btn phone-btn-vol2" aria-hidden="true" />
            <span className="phone-btn phone-btn-power" aria-hidden="true" />
            <div className="phone-screen">
              {SCREENS.map((screen, i) => (
                <div key={screen.file} className={`phone-slide${i === active ? " is-active" : ""}`} aria-hidden={i !== active}>
                  {shot(screen)}
                </div>
              ))}
            </div>
          </div>

          <div className="tour-readout" aria-live="polite">
            <p className="tour-readout-tab">{SCREENS[active].tab}</p>
            <p className="tour-readout-caption">{SCREENS[active].caption}</p>
          </div>

          <div className="tour-controls" onKeyDown={onKey}>
            <button
              type="button"
              className="tour-step"
              onClick={() => goTo(active - 1)}
              disabled={active === 0}
              aria-label="Previous screen"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M15 5 8 12l7 7" />
              </svg>
            </button>

            <div className="tour-dots" role="tablist" aria-label="App screens">
              {SCREENS.map((screen, i) => (
                <button
                  key={screen.file}
                  type="button"
                  role="tab"
                  aria-selected={i === active}
                  tabIndex={i === active ? 0 : -1}
                  className={`tour-dot${i === active ? " is-active" : ""}`}
                  onClick={() => goTo(i)}
                  aria-label={`Show the ${screen.tab} tab`}
                />
              ))}
            </div>

            <button
              type="button"
              className="tour-step"
              onClick={() => goTo(active + 1)}
              disabled={active === SCREENS.length - 1}
              aria-label="Next screen"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="m9 5 7 7-7 7" />
              </svg>
            </button>
          </div>

          {footer ? <div className="tour-get">{footer}</div> : null}
        </div>
      </div>
    </div>
  );
}

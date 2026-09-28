"use client";

import { useEffect } from "react";

/**
 * The motion system for everything below the hero.
 *
 * Entrances arrive in sequence and then retire their stagger delays, drawn
 * lines draw themselves once, ambient loops pause on a hidden tab, and reduced
 * motion is honored live in both directions: flipping it on pins every
 * scroll-drawn element to its finished state, flipping it back off hands them
 * to the drives again.
 */
export default function MotionRoot() {
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    const timers: number[] = [];

    const drawables = Array.from(
      document.querySelectorAll<SVGGeometryElement>("[data-draw]"),
    );

    // Measure each drawn line once so the dash offset has a real length.
    for (const el of drawables) {
      const len = Math.ceil(el.getTotalLength?.() ?? 0);
      if (len > 0) el.style.setProperty("--len", String(len));
    }

    const watched = Array.from(document.querySelectorAll<HTMLElement>(".reveal")) as Array<
      HTMLElement | SVGGeometryElement
    >;
    const all = [...watched, ...drawables];

    const settle = (el: Element) => {
      const delay = Number((el as HTMLElement).style.getPropertyValue("--i") || 0) * 90;
      const id = window.setTimeout(() => el.classList.add("settled"), delay + 900);
      timers.push(id);
    };

    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("in");
          settle(entry.target);
          io.unobserve(entry.target);
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );

    const arm = () => all.forEach((el) => io.observe(el));

    /** Reduced motion, flipped on: every drive stops at its finished state. */
    const pinToFinalStates = () => {
      io.disconnect();
      timers.forEach((t) => window.clearTimeout(t));
      timers.length = 0;
      for (const el of all) {
        el.classList.add("in", "settled");
        if ((el as Element).hasAttribute("data-draw")) el.classList.add("pinned");
      }
    };

    /** Flipped back off: undo the pins so the drives own them again. */
    const unpin = () => {
      for (const el of all) el.classList.remove("pinned");
      all.filter((el) => !el.classList.contains("in")).forEach((el) => io.observe(el));
    };

    const onReduceChange = () => {
      if (reduce.matches) pinToFinalStates();
      else {
        unpin();
        arm();
      }
    };

    if (reduce.matches) pinToFinalStates();
    else arm();

    reduce.addEventListener("change", onReduceChange);

    // Ambient loops never run behind a hidden tab. animation-play-state is not
    // inherited, so the rule has to reach pseudo-elements by itself.
    const onVisibility = () => document.body.classList.toggle("paused", document.hidden);
    document.addEventListener("visibilitychange", onVisibility);
    onVisibility();

    return () => {
      io.disconnect();
      timers.forEach((t) => window.clearTimeout(t));
      reduce.removeEventListener("change", onReduceChange);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return <div className="environment" aria-hidden="true" />;
}

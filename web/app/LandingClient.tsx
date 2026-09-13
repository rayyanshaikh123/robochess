"use client";

import { useEffect } from "react";

/**
 * Client-only wrapper that sets up scroll-triggered fade-in animations
 * for elements with the `.fade-in-up` class.
 */
export default function LandingClient() {
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
          }
        });
      },
      { threshold: 0.1 }
    );

    document.querySelectorAll(".fade-in-up").forEach((el) => {
      observer.observe(el);
    });

    return () => observer.disconnect();
  }, []);

  return null;
}

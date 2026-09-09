"use client";

import { useEffect } from "react";
import ShaderCanvas from "./components/ShaderCanvas";

/**
 * Client-only wrapper that renders the hero WebGL shader background and
 * hooks up the IntersectionObserver for `.fade-in-up` scroll animations.
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

  return (
    <ShaderCanvas className="absolute inset-0 w-full h-full -z-10 opacity-50" />
  );
}

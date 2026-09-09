import Image from "next/image";
import LandingClient from "./LandingClient";

/* ── Static image URLs from Stitch design ── */
const BOARD_IMG =
  "https://lh3.googleusercontent.com/aida-public/AB6AXuBvFx2NuJHWQf__sXbWHYxn8p7Qsc7cIsmYvqaxHEsl5T_Wyq6cmSkArwgJt30UF9wLJX284NugBiZv675JA295da61TGM08u9R-AZfAwy14h-PyZtmmIpsHbw38hEQBOyTc1YcbIXDZCzf-tQqLwM9LBTZdfRp09qRo2gnxy163BAa0Mjm6rE6lUj6hG90FeiiByBlLZLkj47kHXW5t0rZ35OXs3L8q6avvkHbUvqhChcpufJfHJW5aIdOoyZQwoRgIA";

const AVATAR_IMG =
  "https://lh3.googleusercontent.com/aida-public/AB6AXuA0z7jt11Izrf5iFCX4S5UZSqqYbmWA5gDv4R0wnIBXkO9-yukfpqBWTPtTTy2Jov7ccy6vEcBduEwzJZN484SfOmHg9SUSYuOA1GbPKHF-EgreFyf4lF-WoV2x7no_dpK5MFSBEwUH9AbUxRezfH_k08uKRRoYvxQLg80Pigm0cn7wfI6qejIzrO6juCJUCC89krvprFw6eeN3GY_Cgz6xVT_Xxrap69n0Vr5RhwlBl9jiwNpk-byf";

export default function Home() {
  return (
    <>
      {/* Scanline overlay */}
      <div className="scanline-effect" />

      {/* ── TopAppBar ── */}
      <header className="fixed top-0 w-full z-50 bg-background/80 backdrop-blur-md border-b border-outline-variant">
        <div className="flex justify-between items-center px-8 py-4 max-w-[1200px] mx-auto">
          <div className="font-[var(--font-headline)] text-2xl font-bold tracking-widest text-primary-container drop-shadow-[0_0_8px_rgba(195,244,0,0.6)]">
            ROBOCHESS
          </div>
          <nav className="hidden md:flex gap-8">
            {["Features", "Hardware", "Architecture", "Community"].map(
              (item) => (
                <a
                  key={item}
                  href={`#${item.toLowerCase()}`}
                  className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] uppercase text-on-surface-variant hover:text-primary-container transition-colors duration-200"
                >
                  {item}
                </a>
              )
            )}
          </nav>
          <div className="flex items-center gap-4">
            <button className="hidden md:block font-[var(--font-body)] text-xs font-bold tracking-[0.1em] uppercase bg-primary-container text-on-primary-container px-4 py-2 hover:bg-white transition-colors duration-200">
              LAUNCH APP
            </button>
            <span className="material-symbols-outlined text-primary-container hover:text-white cursor-pointer">
              sensors
            </span>
            <Image
              src={AVATAR_IMG}
              alt="User avatar"
              width={32}
              height={32}
              className="w-8 h-8 rounded-full border border-primary-container hidden md:block"
            />
          </div>
        </div>
      </header>

      {/* ── Hero Section ── */}
      <section className="relative min-h-screen flex items-center justify-center pt-20 overflow-hidden">
        <LandingClient />
        <div className="max-w-[1200px] mx-auto px-8 gap-12 items-center relative z-10 flex flex-col justify-center">
          <div className="flex flex-col gap-6 fade-in-up visible text-center">
            <h1 className="font-[var(--font-headline)] text-5xl md:text-[48px] font-bold leading-[1.1] tracking-widest text-primary-container uppercase neon-text">
              THE CONNECTED CHESS PLATFORM
            </h1>
            <p className="font-[var(--font-body)] text-base leading-relaxed text-on-surface max-w-2xl mx-auto">
              Play against humans and AI, detect moves with computer vision,
              analyze with Stockfish, and sync to a physical smart board —
              all from one app.
            </p>
            <div className="flex flex-wrap gap-4 mt-4 justify-center">
              <button className="bg-primary-container text-on-primary-container font-[var(--font-body)] text-xs font-bold tracking-[0.1em] px-6 py-3 hover:shadow-neon transition-all duration-300 uppercase flex items-center gap-2">
                DOWNLOAD FOR IOS
              </button>
              <button className="bg-transparent border border-primary-container text-primary-container font-[var(--font-body)] text-xs font-bold tracking-[0.1em] px-6 py-3 hover:bg-primary-container/10 transition-all duration-300 uppercase">
                ANDROID APK
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* ── Features ── */}
      <section id="features" className="py-24 border-t border-outline-variant relative">
        <div className="max-w-[1200px] mx-auto px-8 flex flex-col items-center justify-center">
          <div className="text-center mb-16 fade-in-up visible">
            <span className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] text-primary-container uppercase mb-2 block">
              What You Can Do
            </span>
            <h2 className="font-[var(--font-headline)] text-[32px] leading-[1.2] font-semibold text-white">
              PLATFORM FEATURES
            </h2>
            <p className="mt-4 max-w-2xl mx-auto text-on-surface-variant font-[var(--font-body)] text-base leading-relaxed">
              Everything a chess player needs — from casual games to
              deep engine analysis to physical board integration.
            </p>
          </div>
          <div className="grid md:grid-cols-3 gap-6 w-full fade-in-up visible">
            {[
              {
                icon: "strategy",
                title: "Play",
                desc: "Human-vs-human and human-vs-AI games with real-time WebSocket updates.",
              },
              {
                icon: "photo_camera",
                title: "Computer Vision",
                desc: "Detect board positions and infer moves from camera frames using YOLO and OpenCV.",
              },
              {
                icon: "query_stats",
                title: "Stockfish Analysis",
                desc: "Deep engine analysis for any position. Review games move-by-move with evaluation graphs.",
              },
              {
                icon: "extension",
                title: "Puzzles",
                desc: "Browse and solve chess puzzles to sharpen your tactical awareness.",
              },
              {
                icon: "mic",
                title: "Voice Commands",
                desc: "Use voice input to enter chess moves hands-free during gameplay.",
              },
              {
                icon: "bluetooth",
                title: "BLE Pairing",
                desc: "Pair with Raspberry Pi board devices over Bluetooth Low Energy for physical play.",
              },
            ].map((feature) => (
              <div
                key={feature.title}
                className="glass-card p-6 group hover:border-primary-container transition-colors cursor-default border-t-2 border-t-surface-container-high hover:border-t-primary-container"
              >
                <span
                  className="material-symbols-outlined text-3xl text-primary-container mb-4 block"
                  style={{ fontVariationSettings: '"FILL" 1' }}
                >
                  {feature.icon}
                </span>
                <h3 className="font-[var(--font-headline)] text-xl font-semibold text-white mb-2">
                  {feature.title}
                </h3>
                <p className="font-[var(--font-body)] text-sm text-on-surface-variant leading-relaxed">
                  {feature.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Hardware Integration ── */}
      <section
        id="hardware"
        className="py-24 border-t border-outline-variant bg-surface-container-lowest"
      >
        <div className="max-w-[1200px] mx-auto px-8 grid md:grid-cols-2 gap-16 items-center">
          <div className="relative fade-in-up visible">
            <Image
              src={BOARD_IMG}
              alt="ROBOCHESS physical smart board with glowing grid lines"
              width={640}
              height={480}
              className="rounded-xl border border-outline-variant w-full"
            />
            <div className="absolute -bottom-4 -right-4 bg-surface p-4 border border-primary-container glass-card shadow-neon">
              <div className="flex items-center gap-3">
                <span className="relative flex h-3 w-3">
                  <span className="animate-ping-slow absolute inline-flex h-full w-full rounded-full bg-primary-container opacity-75" />
                  <span className="relative inline-flex rounded-full h-3 w-3 bg-primary-container" />
                </span>
                <span className="font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] text-white">
                  SYNC: robochess-pi-001
                </span>
              </div>
            </div>
          </div>
          <div className="fade-in-up visible">
            <span className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] text-primary-container uppercase mb-2 block flex items-center gap-2">
              <span className="material-symbols-outlined text-sm">
                bluetooth
              </span>
              RASPBERRY PI INTEGRATION
            </span>
            <h2 className="font-[var(--font-headline)] text-[32px] leading-[1.2] font-semibold text-white mb-6">
              PHYSICAL BOARD. DIGITAL ENGINE. ONE PLATFORM.
            </h2>
            <p className="font-[var(--font-body)] text-base leading-relaxed text-on-surface-variant mb-8">
              The Raspberry Pi edge agent runs a local Stockfish game and
              exposes the board over BLE. It remains the authority for offline
              moves and synchronizes dedicated board sessions when it reconnects
              to the backend. Latency under 12ms.
            </p>
            <div className="grid grid-cols-3 gap-4">
              <div className="p-4 border border-outline-variant bg-surface-container">
                <span className="block font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] text-primary-container mb-1">
                  STATUS
                </span>
                <span className="font-bold text-white uppercase">
                  CONNECTED
                </span>
              </div>
              <div className="p-4 border border-outline-variant bg-surface-container">
                <span className="block font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] text-primary-container mb-1">
                  LATENCY
                </span>
                <span className="font-bold text-white uppercase">11.4 ms</span>
              </div>
              <div className="p-4 border border-outline-variant bg-surface-container">
                <span className="block font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] text-primary-container mb-1">
                  PROTOCOL
                </span>
                <span className="font-bold text-white uppercase">BLE 5.0</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Architecture ── */}
      <section id="architecture" className="py-24 border-t border-outline-variant">
        <div className="max-w-[1200px] mx-auto px-8">
          <div className="text-center mb-16 fade-in-up visible">
            <span className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] text-primary-container uppercase mb-2 block">
              System Design
            </span>
            <h2 className="font-[var(--font-headline)] text-[32px] leading-[1.2] font-semibold text-white mb-2">
              ARCHITECTURE
            </h2>
            <p className="text-on-surface-variant font-[var(--font-body)] text-base leading-relaxed max-w-2xl mx-auto">
              A modular stack connecting mobile, cloud, vision, and edge
              computing.
            </p>
          </div>
          <div className="max-w-4xl mx-auto fade-in-up visible">
            {/* Architecture Diagram */}
            <div className="glass-card border border-outline-variant p-8 rounded-lg">
              <div className="flex flex-col items-center gap-6">
                {/* Flutter App */}
                <div className="w-full max-w-md p-4 border border-primary-container bg-surface-container text-center">
                  <span className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] text-primary-container block mb-1">
                    CLIENT
                  </span>
                  <span className="font-[var(--font-headline)] text-lg font-semibold text-white">
                    Flutter Mobile App
                  </span>
                  <span className="font-[var(--font-body)] text-xs text-on-surface-variant block mt-1">
                    iOS &amp; Android — Clean Architecture
                  </span>
                </div>

                {/* Connection line */}
                <div className="flex flex-col items-center gap-1">
                  <div className="w-px h-6 bg-primary-container/50" />
                  <span className="font-[var(--font-body)] text-[11px] font-medium tracking-[0.05em] text-primary-container bg-surface px-2">
                    REST + WebSocket
                  </span>
                  <div className="w-px h-6 bg-primary-container/50" />
                </div>

                {/* Backend */}
                <div className="w-full max-w-md p-4 border border-outline-variant bg-surface-container-high text-center">
                  <span className="font-[var(--font-body)] text-xs font-bold tracking-[0.1em] text-primary-container block mb-1">
                    SERVER
                  </span>
                  <span className="font-[var(--font-headline)] text-lg font-semibold text-white">
                    FastAPI Backend
                  </span>
                  <span className="font-[var(--font-body)] text-xs text-on-surface-variant block mt-1">
                    Auth · Game Services · Vision Pipeline · Realtime
                  </span>
                </div>

                {/* Services grid */}
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 w-full">
                  {[
                    { label: "MongoDB", icon: "database" },
                    { label: "YOLO / OpenCV", icon: "visibility" },
                    { label: "Stockfish", icon: "psychology" },
                    { label: "Pi Agent", icon: "developer_board" },
                  ].map((svc) => (
                    <div
                      key={svc.label}
                      className="p-3 border border-outline-variant bg-surface-container text-center"
                    >
                      <span className="material-symbols-outlined text-primary-container text-xl block mb-1">
                        {svc.icon}
                      </span>
                      <span className="font-[var(--font-body)] text-[11px] font-bold tracking-[0.05em] text-white uppercase">
                        {svc.label}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Community / Get Started ── */}
      <section
        id="community"
        className="py-24 border-t border-outline-variant bg-surface-container-lowest"
      >
        <div className="max-w-[1200px] mx-auto px-8">
          <div className="text-center mb-16 fade-in-up visible">
            <h2 className="font-[var(--font-headline)] text-[32px] leading-[1.2] font-semibold text-white mb-2">
              GET STARTED
            </h2>
            <p className="text-on-surface-variant font-[var(--font-body)] text-base leading-relaxed max-w-2xl mx-auto">
              Set up the backend, install the app, and connect your board in
              minutes.
            </p>
          </div>
          <div className="max-w-3xl mx-auto fade-in-up visible">
            <div className="glass-card border border-outline-variant p-6 rounded-lg">
              <div className="space-y-4">
                {[
                  {
                    step: "01",
                    title: "Clone & Install Backend",
                    cmd: "pip install -r backend/requirements.txt",
                  },
                  {
                    step: "02",
                    title: "Configure Environment",
                    cmd: "cp .env.example backend/.env  # then edit secrets",
                  },
                  {
                    step: "03",
                    title: "Start the API",
                    cmd: "uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000",
                  },
                  {
                    step: "04",
                    title: "Run the Flutter App",
                    cmd: "cd frontend && flutter pub get && flutter run",
                  },
                ].map((item) => (
                  <div
                    key={item.step}
                    className="flex items-start gap-4 p-4 bg-surface-container hover:bg-surface-container-high transition-colors border-l-2 border-transparent hover:border-primary-container"
                  >
                    <div className="w-10 h-10 bg-surface-bright rounded flex items-center justify-center font-bold text-on-surface-variant shrink-0">
                      {item.step}
                    </div>
                    <div className="min-w-0">
                      <span className="font-bold text-white block mb-1">
                        {item.title}
                      </span>
                      <code className="font-[var(--font-body)] text-[13px] font-medium tracking-[0.02em] text-primary-container bg-deep-charcoal px-2 py-1 rounded block overflow-x-auto">
                        {item.cmd}
                      </code>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Footer ── */}
      <footer className="bg-surface-container-low border-t border-outline-variant w-full relative z-10">
        <div className="flex flex-col md:flex-row justify-between items-center px-8 py-8 gap-4 max-w-[1200px] mx-auto">
          <div className="font-[var(--font-headline)] text-2xl font-semibold text-primary-container">
            ROBOCHESS
          </div>
          <div className="flex flex-wrap justify-center gap-6">
            <a
              className="text-primary-container font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] hover:underline"
              href="#"
            >
              Server Status: ONLINE
            </a>
            {["API Docs", "Privacy Protocol", "Terms of Engagement"].map(
              (link) => (
                <a
                  key={link}
                  className="text-on-surface-variant font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] hover:text-primary-container hover:underline transition-colors"
                  href="#"
                >
                  {link}
                </a>
              )
            )}
          </div>
          <div className="text-on-surface-variant font-[var(--font-body)] text-[13px] font-medium tracking-[0.05em] mt-4 md:mt-0">
            © 2025 ROBOCHESS. ALL RIGHTS RESERVED.
          </div>
        </div>
      </footer>
    </>
  );
}

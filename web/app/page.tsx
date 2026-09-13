import Image from "next/image";
import LandingClient from "./LandingClient";

export default function Home() {
  return (
    <>
      <LandingClient />

      {/* ── Navigation Header ── */}
      <header className="fixed top-0 left-0 right-0 w-full z-50 bg-white/90 backdrop-blur-md border-b border-[var(--color-outline)] shadow-sm">
        <div className="h-20 container flex items-center justify-between">
          <a href="#" className="flex items-center gap-3 group">
            <div className="w-10 h-10 rounded-xl overflow-hidden border border-[var(--color-outline-variant)] bg-[var(--color-surface-low)]">
              <Image
                src="/app_logo.png"
                alt="RoboChess Logo"
                width={40}
                height={40}
                className="w-full h-full object-contain p-0.5"
                priority
              />
            </div>
            <span className="font-[var(--font-headline)] text-2xl font-bold text-[var(--color-primary)] tracking-tight">
              RoboChess
            </span>
          </a>

          <nav className="hidden lg:flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-[var(--color-surface-low)] border border-[var(--color-outline)] shadow-sm">
            <a href="#history" className="text-sm font-semibold px-4 py-1.5 bg-[var(--color-primary)] text-white rounded-full shadow-sm">
              Our Story
            </a>
            <a href="#product" className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors px-4 py-1.5 rounded-full hover:bg-slate-200/50">
              Technology
            </a>
            <a href="#features" className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors px-4 py-1.5 rounded-full hover:bg-slate-200/50">
              Features
            </a>
            <a href="#how-it-works" className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors px-4 py-1.5 rounded-full hover:bg-slate-200/50">
              How It Works
            </a>
            <a href="#why-robochess" className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors px-4 py-1.5 rounded-full hover:bg-slate-200/50">
              Why RoboChess
            </a>
          </nav>

          <div className="flex items-center gap-4">
            <a href="/app/" className="btn-primary inline-flex items-center justify-center text-sm font-semibold px-6 py-2.5">
              Launch App
            </a>
          </div>
        </div>
      </header>

      <main className="w-full pt-20">
        <div className="flex flex-col w-full">

          {/* ── 1. HERO SECTION ── */}
          <section className="relative w-full overflow-hidden pt-16 pb-24 lg:pt-20 lg:pb-32 bg-gradient-to-b from-slate-100/70 via-[var(--color-background)] to-[var(--color-background)]">
            {/* Ambient Green Accent Glow */}
            <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[700px] h-[500px] bg-[var(--color-primary)]/5 rounded-full blur-[120px] pointer-events-none" />

            <div className="container flex flex-col items-center text-center relative z-10">
              {/* Pill Tagline */}
              <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white border border-[var(--color-outline)] shadow-sm mb-6 fade-in-up">
                <span className="w-2 h-2 rounded-full bg-emerald-600 animate-pulse" />
                <span className="text-xs font-semibold text-[var(--color-primary)] uppercase tracking-wider font-[var(--font-body)]">
                  The Connected Chess Platform
                </span>
              </div>

              {/* Headline */}
              <h1 className="font-[var(--font-headline)] text-4xl sm:text-5xl lg:text-[68px] lg:leading-[76px] font-extrabold tracking-tight text-slate-900 max-w-5xl mb-6 fade-in-up">
                From <span className="text-[var(--color-primary)] font-black">Ancient Strategy</span> to the Future of Chess
              </h1>

              {/* Supporting Text */}
              <p className="font-[var(--font-body)] text-lg text-slate-600 max-w-2xl mb-10 leading-relaxed fade-in-up">
                Experience chess through a smart, interactive robotic chessboard seamlessly synchronized with modern computer vision, AI opponents, and intelligent mobile play.
              </p>

              {/* Dual CTAs */}
              <div className="flex flex-wrap items-center justify-center gap-4 mb-16 fade-in-up">
                <a href="/app/" className="btn-primary inline-flex items-center gap-2 text-base font-semibold px-8 py-3.5">
                  <span className="material-symbols-outlined text-[20px]">play_arrow</span>
                  <span>Launch Web App</span>
                </a>
                <a href="#history" className="inline-flex items-center gap-2 bg-white hover:bg-slate-50 text-slate-800 border border-[var(--color-outline)] text-base font-semibold px-8 py-3.5 rounded-full shadow-sm hover:border-slate-300 transition-all">
                  <span className="material-symbols-outlined text-[20px] text-[var(--color-primary)]">auto_stories</span>
                  <span>Explore Our Story</span>
                </a>
              </div>

              {/* Hero Showcase Image */}
              <div className="relative w-full max-w-5xl mx-auto rounded-2xl overflow-hidden bg-white p-2 border border-[var(--color-outline)] shadow-xl group fade-in-up">
                <div className="relative aspect-[16/9] w-full overflow-hidden rounded-xl bg-slate-900">
                  <Image
                    src="https://lh3.googleusercontent.com/aida/AEtjO1W5h3Ugbe2MWGpbf02-QLd7Ykxu0meiDQv7fg5QEr3g02MkGMuDHUkaHBglMr7H4oIf5IF5RAI8X8hZ-uuPg9IusY9U-wAvR4qWSsvXnQkfqnlUYvGDK56y8AdyFQX0SSfOYWbSpFyPzAKt8Sb_zlZq-ns86cpVCdlywpVbj5yWTD4335gDd1VNJNLfOPCT2jLYj4F16P68pFb3cDJsLllCCj0g9Wp_A7MmcH5xBbOWh-cARlAWrlZ1F3I"
                    alt="RoboChess Smart Robotic Chessboard with glowing moves"
                    width={1280}
                    height={720}
                    className="w-full h-full object-cover object-center transform group-hover:scale-[1.01] transition-transform duration-700 ease-out"
                    unoptimized
                  />
                </div>
              </div>
            </div>
          </section>

          {/* ── 2. HISTORY SECTION ── */}
          <section className="w-full py-24 bg-white border-y border-[var(--color-outline)] relative" id="history">
            <div className="container flex flex-col gap-14 relative z-10">
              {/* Section Title */}
              <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 pb-6 border-b border-[var(--color-outline)] fade-in-up">
                <div className="max-w-2xl">
                  <div className="inline-flex items-center gap-2 px-3.5 py-1 rounded-full bg-slate-100 border border-[var(--color-outline)] text-[var(--color-primary)] text-xs uppercase tracking-wider mb-4 font-semibold">
                    <span className="material-symbols-outlined text-[15px]">account_balance</span>
                    <span>Historical Provenance</span>
                  </div>
                  <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900">
                    Where Chess Began
                  </h2>
                  <p className="font-[var(--font-body)] text-slate-600 mt-3 leading-relaxed">
                    An unbroken continuum of strategic thought across 1,500 years. The transformation from an ancient Sanskrit tactical science into physical artificial intelligence.
                  </p>
                </div>
                <div className="flex items-center gap-3">
                  <div className="px-4 py-2 rounded-xl bg-amber-50 border border-amber-200 text-amber-900 text-xs uppercase tracking-widest font-semibold">
                    Sanskrit: चतुरंग (Caturaṅga)
                  </div>
                </div>
              </div>

              {/* Archival Artifact */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 items-center p-8 lg:p-10 rounded-2xl bg-[var(--color-surface-low)] border border-[var(--color-outline)] shadow-sm fade-in-up">
                <div className="lg:col-span-6 relative overflow-hidden rounded-xl bg-white border border-[var(--color-outline)] p-2 shadow-sm group">
                  <Image
                    src="https://lh3.googleusercontent.com/aida/AEtjO1W05pphxyKflm0UbleWq_SxHIj1mIBLoWHRtkZadkoBFnkPpWXtaVAoWbHAthjEeGB9EjuwxLsmULqECoLn28E9a3Km6lL7DlO0LqnJgN1UvwsMKybqXdjiIPex3obQGJll5a5QmAT7a-ByjzVdoAccK4E_zVGuyfyrPG1CCnESdzHOnXmTZ5d3ELntMOjyykQ7MjH7egfW33onjrGJL1MiHhTavSFH3DXqHcxmIgWksuJ3LEcUX1uLR9w"
                    alt="Original Indian Chaturanga Ancient Manuscript"
                    width={800}
                    height={600}
                    className="w-full h-auto object-cover rounded-lg shadow-sm transition-transform duration-500 group-hover:scale-[1.01]"
                    unoptimized
                  />
                  <div className="mt-3 bg-white px-3.5 py-2.5 rounded-lg border border-[var(--color-outline)] flex items-center justify-between">
                    <span className="text-xs font-semibold text-slate-800">Historical Parchment Archetype • Ashtapada (8×8) Grid</span>
                    <span className="text-[11px] text-slate-500 uppercase tracking-wider font-mono">Circa Gupta Era</span>
                  </div>
                </div>
                <div className="lg:col-span-6 flex flex-col justify-center gap-5">
                  <div className="flex items-center gap-3">
                    <span className="w-8 h-1 rounded-full bg-[var(--color-primary)]" />
                    <span className="text-xs font-bold uppercase tracking-widest text-[var(--color-primary)]">The Sacred Quadripartite Army</span>
                  </div>
                  <h3 className="font-[var(--font-headline)] text-2xl lg:text-3xl font-bold text-slate-900">
                    &ldquo;Chatur-Anga&rdquo;: The Four Limbs of War
                  </h3>
                  <p className="font-[var(--font-body)] text-slate-600 leading-relaxed">
                    Conceived during the 6th century in Northern India, Chaturanga mirrored the four classic divisions of the Indian army: Infantry (Pawn), Cavalry (Knight), Elephant (Bishop), and Chariot (Rook), organized around the King and his Chief Strategist (Mantri).
                  </p>
                  <div className="grid grid-cols-2 gap-3.5 pt-2">
                    {[
                      { name: "Padati (Infantry)", desc: "Modern Pawn. Ground foot-soldiers advancing square by square." },
                      { name: "Ashwa (Cavalry)", desc: "Modern Knight. Agile leaping mounts traversing defensive lines." },
                      { name: "Gaja (Elephant)", desc: "Modern Bishop. Powerful siege animals striking along diagonal flanks." },
                      { name: "Ratha (Chariot)", desc: "Modern Rook. Heavy battlefield chariots cutting straight vectors." },
                    ].map((unit) => (
                      <div key={unit.name} className="p-4 rounded-xl bg-white border border-[var(--color-outline)] shadow-sm flex flex-col gap-1">
                        <span className="text-xs text-[var(--color-wood-dark)] uppercase font-bold tracking-wider font-mono">{unit.name}</span>
                        <span className="text-xs text-slate-600">{unit.desc}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* Timeline */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 fade-in-up">
                {[
                  { num: "01", era: "6th Century", title: "Ancient India", desc: "Gupta Empire origin. Conceived on the uncheckered Ashtapada 8×8 board as a philosophical simulator of military strategy.", tag: "Birth of the Royal Game", tagColor: "text-[var(--color-primary)]", highlight: false },
                  { num: "02", era: "7th–15th Cent.", title: "Persia to Europe", desc: "Transitioned to Persian Shatranj, traversing silk trade routes to European nobility. The Mantri evolved into the devastatingly powerful Queen.", tag: "Global Dispersion", tagColor: "text-[var(--color-wood-dark)]", highlight: false },
                  { num: "03", era: "19th–20th Cent.", title: "Universal Standardization", desc: "FIDE codification, Staunton design, world championship rivalries, and the shift toward cold, flat glass computer screens.", tag: "The Digital Pivot", tagColor: "text-slate-600", highlight: false },
                  { num: "04", era: "Today & Beyond", title: "Robotic Reimagination", desc: "RoboChess merges ancient tangible wood craftsmanship with autonomous sub-surface robotics and machine vision telemetry.", tag: "The Living Board", tagColor: "text-emerald-200", highlight: true },
                ].map((stage) => (
                  <div key={stage.num} className={`p-6 rounded-xl flex flex-col justify-between group transition-all ${stage.highlight ? "bg-[var(--color-primary)] text-white shadow-md" : "bg-white border border-[var(--color-outline)] shadow-sm hover:border-slate-300 hover:shadow-md"}`}>
                    <div>
                      <div className="flex items-center justify-between mb-4">
                        <span className={`font-[var(--font-headline)] text-3xl font-bold ${stage.highlight ? "text-emerald-300" : "text-[var(--color-primary)]"}`}>{stage.num}</span>
                        <span className={`px-2.5 py-0.5 rounded-full text-xs font-semibold ${stage.highlight ? "bg-white/20 text-emerald-100" : "bg-slate-100 text-slate-700"}`}>{stage.era}</span>
                      </div>
                      <h4 className={`font-[var(--font-headline)] text-lg font-bold mb-2 ${stage.highlight ? "text-white" : "text-slate-900 group-hover:text-[var(--color-primary)]"} transition-colors`}>{stage.title}</h4>
                      <p className={`text-sm leading-relaxed ${stage.highlight ? "text-emerald-100/80" : "text-slate-600"}`}>{stage.desc}</p>
                    </div>
                    <div className={`mt-6 pt-4 border-t flex items-center gap-2 text-xs font-semibold uppercase ${stage.highlight ? "border-white/20 " + stage.tagColor : "border-slate-100 " + stage.tagColor}`}>
                      {stage.highlight && <span className="material-symbols-outlined text-[16px]">precision_manufacturing</span>}
                      <span>{stage.tag}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* ── 3. PRODUCT SECTION ── */}
          <section className="w-full py-24 bg-[var(--color-background)] relative" id="product">
            <div className="container flex flex-col gap-14 relative z-10">
              <div className="text-center max-w-3xl mx-auto flex flex-col items-center fade-in-up">
                <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] px-3.5 py-1 rounded-full bg-emerald-50 border border-emerald-200 font-semibold mb-3">
                  Hardware &amp; Optical Architecture
                </span>
                <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900">
                  Meet RoboChess
                </h2>
                <p className="font-[var(--font-body)] text-slate-600 mt-4 leading-relaxed">
                  RoboChess brings physical chess and digital convenience together. An overhead vision scanner tracks every square in real time, while a robotic magnetic X-Y gantry silently glides pieces across the surface.
                </p>
              </div>

              {/* Cutaway Showcase */}
              <div className="relative rounded-2xl bg-white border border-[var(--color-outline)] p-6 lg:p-10 shadow-md fade-in-up">
                <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
                  <div className="lg:col-span-7 relative rounded-xl overflow-hidden bg-slate-900 border border-slate-800">
                    <Image
                      src="https://lh3.googleusercontent.com/aida/AEtjO1WivIydrp5DVzrLoPTpHxP5ZJmEJeAfT--GZfDXek1q257SZnwzgIFC89Vf7rQ_YjqJM6XNvirTodBV8FCIi2Jggm9tpxnb9RtX9TTHlHWhOuswQ6XNbCk5-akc8YOZsVlEkQN0k-ItK7e0JlRuPnBNW5M892m3avr6kgU8G0zDFMK7fRc_3yJIAVwUaj5XLUVSQHRqSm_1FLnW_Hyg65eTiDl46pmUn6jAyalBVNplci5M5cKiaFOoNno"
                      alt="RoboChess Robotic Chess System Cutaway Mechanism"
                      width={1200}
                      height={896}
                      className="w-full h-auto object-cover rounded-xl"
                      unoptimized
                    />

                  </div>

                  <div className="lg:col-span-5 flex flex-col gap-4">
                    {[
                      { icon: "videocam", title: "Overhead Vision Sensor", desc: "Continuous neural pose estimation and spatial piece tracking with rapid occlusion recovery and 99.8% square validation accuracy.", color: "text-[var(--color-primary)]" },
                      { icon: "lens_blur", title: "Magnetic Core Actuator", desc: "High-flux neodymium electromagnet coupled with silent dampeners provides a whisper-quiet, frictionless piece glide under all 64 squares.", color: "text-[var(--color-wood-dark)]" },
                      { icon: "swap_horiz", title: "Precision Dual-Axis X-Y Gantry", desc: "Industrial-grade ground linear rails concealed beneath tournament surface, executing complex diagonal and knight step-paths.", color: "text-[var(--color-primary)]" },
                      { icon: "wifi_tethering", title: "Mobile Wireless Engine", desc: "Integrated dual BLE 5.3 and Wi-Fi 6 telemetry link for millisecond cloud engine synchronization and frictionless peer matchups.", color: "text-slate-700" },
                    ].map((item) => (
                      <div key={item.title} className="p-4 rounded-xl bg-[var(--color-surface-low)] border border-[var(--color-outline)] hover:bg-white hover:border-slate-300 transition-all">
                        <div className="flex items-start gap-3.5">
                          <div className={`w-10 h-10 rounded-xl bg-white border border-[var(--color-outline)] ${item.color} flex items-center justify-center shrink-0 shadow-sm`}>
                            <span className="material-symbols-outlined text-[20px]">{item.icon}</span>
                          </div>
                          <div>
                            <h4 className="font-[var(--font-headline)] text-base font-bold text-slate-900">{item.title}</h4>
                            <p className="text-xs text-slate-600 mt-1 leading-relaxed">{item.desc}</p>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* ── 4. KEY FEATURES ── */}
          <section className="w-full py-24 bg-white border-y border-[var(--color-outline)]" id="features">
            <div className="container flex flex-col gap-14">
              <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 pb-4 fade-in-up">
                <div>
                  <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 font-semibold">Autonomous Precision</span>
                  <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900 mt-3">
                    Master-Level Capabilities
                  </h2>
                </div>
                <p className="font-[var(--font-body)] text-slate-600 max-w-md">
                  Engineered to satisfy the tactical rigor of FIDE Grandmasters while remaining intuitive, inviting, and inspiring for every casual strategist.
                </p>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 fade-in-up">
                {[
                  { icon: "visibility", title: "Computer Vision Detection", desc: "Detects the chessboard and pieces using an ultra-low latency overhead camera. Recognizes natural human hand moves and validates legal squares instantaneously.", tag: "Neural Scan Grid", tagIcon: "grain", accent: "primary" },
                  { icon: "precision_manufacturing", title: "Automatic Piece Movement", desc: "Moves chess pieces autonomously with a subterranean magnetic X-Y gantry mechanism. Your opponent's moves materialize on the board like magic.", tag: "Vector Motion Control", tagIcon: "alt_route", accent: "wood" },
                  { icon: "public", title: "Remote Play Anywhere", desc: "Play board-to-board or board-to-app games across continents. Feel your remote opponent's strategy physically transpire directly in front of you.", tag: "Global Node Sync", tagIcon: "hub", accent: "primary" },
                  { icon: "mic", title: "Voice-Based Moves", desc: "Make moves hands-free using simple spoken voice commands like \"Knight to F3\" or \"E2 to E4\". Ideal for accessible play and unencumbered analysis.", tag: "Acoustic NLP Pipeline", tagIcon: "graphic_eq", accent: "wood" },
                  { icon: "podcasts", title: "Smart Connectivity", desc: "Connect effortlessly to the board, mobile companion, and leading tournament databases via dual-channel Bluetooth Low Energy and high-speed Wi-Fi.", tag: "BLE 5.3 & Wi-Fi 6", tagIcon: "router", accent: "primary" },
                  { icon: "school", title: "Interactive Learning", desc: "Make chess engaging and accessible for beginners and young learners with real-time tactical blunders, puzzle replays, and adaptive AI coaching.", tag: "Adaptive AI Coach", tagIcon: "psychology", accent: "wood" },
                ].map((f) => {
                  const isPrimary = f.accent === "primary";
                  const accentColor = isPrimary ? "var(--color-primary)" : "var(--color-wood-dark)";
                  return (
                    <div key={f.title} className={`p-8 rounded-2xl bg-[var(--color-surface-low)] border border-[var(--color-outline)] flex flex-col justify-between transition-all group ${isPrimary ? "hover:border-[var(--color-primary)]/40" : "hover:border-[var(--color-wood-dark)]/50"} hover:shadow-md`}>
                      <div className="flex flex-col gap-4">
                        <div className={`w-12 h-12 rounded-xl bg-white border border-[var(--color-outline)] flex items-center justify-center shadow-sm transition-all`} style={{ color: accentColor }}>
                          <span className="material-symbols-outlined text-[24px]">{f.icon}</span>
                        </div>
                        <h3 className="font-[var(--font-headline)] text-xl font-bold text-slate-900 transition-colors">{f.title}</h3>
                        <p className="text-sm text-slate-600 leading-relaxed">{f.desc}</p>
                      </div>
                      <div className="mt-8 pt-4 border-t border-slate-200 flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
                        <span>{f.tag}</span>
                        <span className="material-symbols-outlined text-[16px]" style={{ color: accentColor }}>{f.tagIcon}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </section>

          {/* ── 5. HOW IT WORKS ── */}
          <section className="w-full py-24 bg-[var(--color-background)] relative" id="how-it-works">
            <div className="container flex flex-col gap-14 relative z-10">
              <div className="text-center max-w-2xl mx-auto fade-in-up">
                <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 mb-3 inline-block font-semibold">
                  Intuitive Setup
                </span>
                <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900">
                  How It Works
                </h2>
                <p className="font-[var(--font-body)] text-slate-600 mt-2">
                  From unboxing to your first autonomous grandmaster duel in under three minutes.
                </p>
              </div>

              <div className="relative grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8 fade-in-up">
                <div className="hidden lg:block absolute top-12 left-[12%] right-[12%] h-[2px] bg-slate-200 pointer-events-none" />
                {[
                  { icon: "smartphone", step: "Step 01", title: "Download the App", desc: "Install the companion RoboChess mobile application seamlessly on iOS or Android." },
                  { icon: "bluetooth_connected", step: "Step 02", title: "Connect Your Board", desc: "Pair your physical robotic chessboard instantly via single-touch Bluetooth or Wi-Fi." },
                  { icon: "sports_esports", step: "Step 03", title: "Start Playing", desc: "Choose your mode: challenge an adaptive grandmaster engine, play a remote friend, or enter ranked matchmaking." },
                  { icon: "magic_button", step: "Step 04", title: "Watch the Board Move", desc: "Computer vision detects your physical move and the internal robotic mechanism glides the response autonomously." },
                ].map((s) => (
                  <div key={s.step} className="relative flex flex-col items-center text-center group">
                    <div className="w-20 h-20 rounded-2xl bg-white border-2 border-[var(--color-outline)] flex items-center justify-center text-[var(--color-primary)] shadow-sm mb-5 z-10 group-hover:border-[var(--color-primary)] group-hover:scale-105 transition-all">
                      <span className="material-symbols-outlined text-[32px]">{s.icon}</span>
                    </div>
                    <span className="text-xs text-[var(--color-primary)] uppercase tracking-widest font-bold mb-1">{s.step}</span>
                    <h3 className="font-[var(--font-headline)] text-lg font-bold text-slate-900 mb-1.5">{s.title}</h3>
                    <p className="text-xs text-slate-600 leading-relaxed max-w-xs">{s.desc}</p>
                  </div>
                ))}
              </div>
            </div>
          </section>

          {/* ── 6. GAME MODES ── */}
          <section className="w-full py-24 bg-white border-y border-[var(--color-outline)] relative">
            <div className="container flex flex-col gap-14">
              <div className="text-center max-w-2xl mx-auto fade-in-up">
                <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 mb-3 inline-block font-semibold">Flexible Strategy</span>
                <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900">
                  Three Ways to Experience the Game
                </h2>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-8 fade-in-up">
                {/* Mode 1 */}
                <div className="p-8 rounded-2xl bg-[var(--color-surface-low)] border border-[var(--color-outline)] flex flex-col justify-between hover:shadow-md transition-all group">
                  <div>
                    <div className="w-12 h-12 rounded-xl bg-white border border-[var(--color-outline)] text-[var(--color-primary)] flex items-center justify-center mb-6 shadow-sm">
                      <span className="material-symbols-outlined text-[26px]">token</span>
                    </div>
                    <span className="text-xs text-[var(--color-primary)] uppercase tracking-wider font-bold">Mode 01</span>
                    <h3 className="font-[var(--font-headline)] text-xl font-bold text-slate-900 mt-1.5 mb-3">On the Physical Board</h3>
                    <p className="text-sm text-slate-600 leading-relaxed">
                      Relish authentic wood-grained piece textures, weighted bases, and the tactile thrill of chess while the board responds completely on its own.
                    </p>
                  </div>
                  <div className="mt-8 pt-6 border-t border-slate-200">
                    <ul className="flex flex-col gap-2 text-xs text-slate-600">
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-700 text-[18px]">check_circle</span>Tactile handcrafted Staunton pieces</li>
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-700 text-[18px]">check_circle</span>Autonomous opponent movements</li>
                    </ul>
                  </div>
                </div>

                {/* Mode 2 — Highlighted */}
                <div className="p-8 rounded-2xl bg-[var(--color-primary)] text-white flex flex-col justify-between shadow-lg relative overflow-hidden group">
                  <div className="relative z-10">
                    <div className="w-12 h-12 rounded-xl bg-white/15 text-emerald-200 border border-white/20 flex items-center justify-center mb-6">
                      <span className="material-symbols-outlined text-[26px]">language</span>
                    </div>
                    <span className="text-xs text-emerald-300 uppercase tracking-wider font-bold">Mode 02</span>
                    <h3 className="font-[var(--font-headline)] text-xl font-bold text-white mt-1.5 mb-3">With a Friend Remotely</h3>
                    <p className="text-sm text-emerald-100/90 leading-relaxed">
                      Play board-to-board with players across the globe. When they touch their rook in London, your rook mirrors the exact glide in Tokyo.
                    </p>
                  </div>
                  <div className="mt-8 pt-6 border-t border-white/20 relative z-10">
                    <ul className="flex flex-col gap-2 text-xs text-emerald-100">
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-300 text-[18px]">check_circle</span>Live board-to-board synchronization</li>
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-300 text-[18px]">check_circle</span>Sub-second move transmission latency</li>
                    </ul>
                  </div>
                </div>

                {/* Mode 3 */}
                <div className="p-8 rounded-2xl bg-[var(--color-surface-low)] border border-[var(--color-outline)] flex flex-col justify-between hover:shadow-md transition-all group">
                  <div>
                    <div className="w-12 h-12 rounded-xl bg-white border border-[var(--color-outline)] text-[var(--color-primary)] flex items-center justify-center mb-6 shadow-sm">
                      <span className="material-symbols-outlined text-[26px]">devices</span>
                    </div>
                    <span className="text-xs text-[var(--color-primary)] uppercase tracking-wider font-bold">Mode 03</span>
                    <h3 className="font-[var(--font-headline)] text-xl font-bold text-slate-900 mt-1.5 mb-3">Through Companion App</h3>
                    <p className="text-sm text-slate-600 leading-relaxed">
                      Play purely digital matches on the subway or at your desk. Your moves instantly actuate onto your home board for spectators, family, or coaching students.
                    </p>
                  </div>
                  <div className="mt-8 pt-6 border-t border-slate-200">
                    <ul className="flex flex-col gap-2 text-xs text-slate-600">
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-700 text-[18px]">check_circle</span>Simultaneous 2D/3D board perspective</li>
                      <li className="flex items-center gap-2"><span className="material-symbols-outlined text-emerald-700 text-[18px]">check_circle</span>Instant PGN export &amp; cloud archive</li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* ── 7. WHY ROBOCHESS ── */}
          <section className="w-full py-24 bg-[var(--color-background)] relative" id="why-robochess">
            <div className="container flex flex-col gap-14 relative z-10">
              <div className="text-center max-w-3xl mx-auto fade-in-up">
                <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 mb-3 inline-block font-semibold">The Philosophy</span>
                <h2 className="font-[var(--font-headline)] text-3xl lg:text-4xl font-bold text-slate-900">
                  Why Choose RoboChess?
                </h2>
                <p className="font-[var(--font-body)] text-slate-600 mt-3">
                  Where sacred cultural ancestry meets uncompromising modern engineering.
                </p>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 fade-in-up">
                {/* Heritage */}
                <div className="p-8 lg:p-10 rounded-2xl bg-white border border-[var(--color-outline)] shadow-sm flex flex-col gap-6">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-xl bg-amber-50 border border-amber-200 text-[var(--color-wood-dark)] flex items-center justify-center">
                      <span className="material-symbols-outlined text-[22px]">history_edu</span>
                    </div>
                    <span className="text-xs uppercase tracking-widest text-[var(--color-wood-dark)] font-bold">Ancient Chaturanga Heritage</span>
                  </div>
                  <h3 className="font-[var(--font-headline)] text-2xl font-bold text-slate-900">Honoring the Cradle of Strategic Intellect</h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    RoboChess re-centers the narrative, celebrating India&apos;s foundational gift of strategic quadripartite geometry to human civilization.
                  </p>
                  <div className="flex flex-col gap-4 mt-2">
                    {[
                      { title: "Connects Indian Heritage with Modern Tech", desc: "Celebrates the Ashtapada origin story through thoughtful design accents and archival commentary." },
                      { title: "Physical & Tactile Connection", desc: "Combats screen fatigue by returning chess to the satisfying feel of tangible weighted timber." },
                      { title: "Accessible & Hands-Free Interaction", desc: "Voice commands empower motor-impaired players and children to direct physical pieces easily." },
                    ].map((item) => (
                      <div key={item.title} className="flex items-start gap-3">
                        <span className="material-symbols-outlined text-[var(--color-primary)] text-[20px] mt-0.5">verified</span>
                        <div>
                          <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 block">{item.title}</span>
                          <span className="text-xs text-slate-600">{item.desc}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Innovation */}
                <div className="p-8 lg:p-10 rounded-2xl bg-white border border-[var(--color-outline)] shadow-sm flex flex-col gap-6">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-xl bg-emerald-50 border border-emerald-200 text-[var(--color-primary)] flex items-center justify-center">
                      <span className="material-symbols-outlined text-[22px]">memory</span>
                    </div>
                    <span className="text-xs uppercase tracking-widest text-[var(--color-primary)] font-bold">Modern Innovation &amp; Robotics</span>
                  </div>
                  <h3 className="font-[var(--font-headline)] text-2xl font-bold text-slate-900">Pioneering Accessible Mechatronics</h3>
                  <p className="text-sm text-slate-600 leading-relaxed">
                    Historic robotic boards cost upwards of thousands of dollars and locked players into rigid proprietary networks. We engineered RoboChess to democratize robotic chess for everyone.
                  </p>
                  <div className="flex flex-col gap-4 mt-2">
                    {[
                      { title: "STEM & Robotics Inspiration", desc: "Demystifies computer vision, magnetic actuation, and inverse kinematics for schools and young thinkers." },
                      { title: "Affordable Luxury Engineering", desc: "High-efficiency gantry design delivers precision at a fraction of legacy board costs." },
                      { title: "Modular & Upgradeable Platform", desc: "Swap chess sets easily and receive over-the-air firmware upgrades for newer chess engines and analysis models." },
                    ].map((item) => (
                      <div key={item.title} className="flex items-start gap-3">
                        <span className="material-symbols-outlined text-emerald-700 text-[20px] mt-0.5">check_circle</span>
                        <div>
                          <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 block">{item.title}</span>
                          <span className="text-xs text-slate-600">{item.desc}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </section>

          {/* ── 8. DOWNLOAD SECTION ── */}
          <section className="w-full py-24 bg-white border-y border-[var(--color-outline)] relative overflow-hidden" id="download">
            <div className="container rounded-3xl bg-[var(--color-primary)] text-white p-8 lg:p-14 shadow-xl relative z-10 overflow-hidden fade-in-up">
              {/* Ambient glow */}
              <div className="absolute -right-20 -bottom-20 w-96 h-96 bg-emerald-500/20 rounded-full blur-3xl pointer-events-none" />

              <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 items-center">
                <div className="lg:col-span-7 flex flex-col gap-5">
                  <div className="inline-flex items-center gap-2 px-3.5 py-1 rounded-full bg-white/15 border border-white/20 text-emerald-200 text-xs uppercase tracking-wider w-fit font-semibold">
                    <span className="material-symbols-outlined text-[15px]">cell_tower</span>
                    <span>Mobile Companion Available Now</span>
                  </div>
                  <h2 className="font-[var(--font-headline)] text-3xl sm:text-4xl lg:text-5xl font-extrabold text-white leading-tight">
                    Carry the Future of Chess in Your Pocket
                  </h2>
                  <p className="font-[var(--font-body)] text-emerald-100/90 max-w-xl leading-relaxed">
                    Download the RoboChess application to unlock live board telemetry, real-time Grandmaster evaluations, voice commands, and worldwide peer matchmaking.
                  </p>

                  {/* App Store Buttons */}
                  <div className="flex flex-wrap items-center gap-4 pt-2">
                    <a href="https://github.com/rayyanshaikh123/robochess" target="_blank" rel="noopener noreferrer" className="flex items-center gap-3.5 px-6 py-3 rounded-xl bg-white text-slate-900 hover:bg-slate-100 shadow-sm transition-all">
                      <span className="material-symbols-outlined text-slate-900 text-[28px]">phone_iphone</span>
                      <div className="flex flex-col text-left">
                        <span className="text-[10px] text-slate-500 uppercase leading-none font-semibold">Download on the</span>
                        <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 leading-tight">Apple App Store</span>
                      </div>
                    </a>
                    <a href="https://github.com/rayyanshaikh123/robochess" target="_blank" rel="noopener noreferrer" className="flex items-center gap-3.5 px-6 py-3 rounded-xl bg-white text-slate-900 hover:bg-slate-100 shadow-sm transition-all">
                      <span className="material-symbols-outlined text-slate-900 text-[28px]">android</span>
                      <div className="flex flex-col text-left">
                        <span className="text-[10px] text-slate-500 uppercase leading-none font-semibold">Get it on</span>
                        <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 leading-tight">Google Play Store</span>
                      </div>
                    </a>
                  </div>

                  {/* Trust Badges */}
                  <div className="flex flex-wrap items-center gap-6 pt-5 border-t border-white/20 text-emerald-100/90 text-xs">
                    <div className="flex items-center gap-2">
                      <span className="material-symbols-outlined text-emerald-300 text-[18px]">bluetooth</span>
                      <span>BLE 5.3 Low Energy</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="material-symbols-outlined text-emerald-300 text-[18px]">security</span>
                      <span>FIDE Engine Compatible</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="material-symbols-outlined text-emerald-300 text-[18px]">money_off</span>
                      <span>Zero Subscription for Core Play</span>
                    </div>
                  </div>
                </div>

                {/* QR Code */}
                <div className="lg:col-span-5 flex flex-col items-center justify-center gap-5 p-8 rounded-2xl bg-white text-slate-900 shadow-lg border border-[var(--color-outline)]">
                  <div className="p-3 bg-slate-50 rounded-xl border border-[var(--color-outline)] shadow-inner flex flex-col items-center justify-center">
                    <svg className="w-32 h-32 text-slate-900" fill="currentColor" viewBox="0 0 100 100">
                      <rect fill="currentColor" height="30" rx="3" width="30" x="0" y="0" />
                      <rect fill="#fff" height="20" rx="1.5" width="20" x="5" y="5" />
                      <rect fill="currentColor" height="10" rx="1" width="10" x="10" y="10" />
                      <rect fill="currentColor" height="30" rx="3" width="30" x="70" y="0" />
                      <rect fill="#fff" height="20" rx="1.5" width="20" x="75" y="5" />
                      <rect fill="currentColor" height="10" rx="1" width="10" x="80" y="10" />
                      <rect fill="currentColor" height="30" rx="3" width="30" x="0" y="70" />
                      <rect fill="#fff" height="20" rx="1.5" width="20" x="5" y="75" />
                      <rect fill="currentColor" height="10" rx="1" width="10" x="10" y="80" />
                      <rect fill="currentColor" height="6" width="6" x="38" y="8" />
                      <rect fill="currentColor" height="12" width="6" x="48" y="14" />
                      <rect fill="currentColor" height="6" width="6" x="58" y="6" />
                      <rect fill="currentColor" height="24" rx="2" width="24" x="38" y="38" />
                      <rect fill="#fff" height="12" rx="1" width="12" x="44" y="44" />
                      <rect fill="currentColor" height="16" width="8" x="72" y="38" />
                      <rect fill="currentColor" height="8" width="8" x="86" y="44" />
                      <rect fill="currentColor" height="8" width="12" x="38" y="72" />
                      <rect fill="currentColor" height="18" width="8" x="56" y="72" />
                      <rect fill="currentColor" height="8" width="22" x="72" y="72" />
                      <rect fill="currentColor" height="10" width="10" x="84" y="86" />
                    </svg>
                  </div>
                  <div className="flex flex-col text-center">
                    <span className="font-[var(--font-headline)] text-base font-bold text-slate-900">Scan to Install</span>
                    <span className="text-xs text-slate-500 mt-1 max-w-xs">Point your camera to sync your iOS or Android device directly with your chessboard</span>
                  </div>
                </div>
              </div>
            </div>
          </section>
        </div>
      </main>

      {/* ── Footer ── */}
      <footer className="w-full bg-slate-100 border-t border-[var(--color-outline)] text-slate-600">
        <div className="container py-16">
          <div className="grid grid-cols-1 md:grid-cols-12 gap-10">
            <div className="md:col-span-5 flex flex-col gap-4">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-lg overflow-hidden border border-[var(--color-outline-variant)] bg-[var(--color-surface-low)]">
                  <Image
                    src="/app_logo.png"
                    alt="RoboChess"
                    width={32}
                    height={32}
                    className="w-full h-full object-contain p-0.5"
                  />
                </div>
                <span className="font-[var(--font-headline)] text-xl font-bold text-slate-900">RoboChess</span>
              </div>
              <p className="font-[var(--font-body)] text-sm text-slate-700 font-semibold max-w-md">From ancient strategy to intelligent gameplay.</p>
              <p className="text-xs text-slate-500 max-w-sm leading-relaxed">Re-architecting the sacred geometry of the 64 squares through autonomous robotics, computer vision, and grandmaster tactical engines.</p>
              <div className="flex items-center gap-2 pt-2">
                {["public", "terminal", "neurology", "podcasts"].map((icon) => (
                  <a key={icon} className="w-9 h-9 rounded-full bg-white border border-[var(--color-outline)] flex items-center justify-center text-slate-600 hover:text-[var(--color-primary)] hover:border-[var(--color-primary)] transition-all shadow-sm" href="#">
                    <span className="material-symbols-outlined text-[17px]">{icon}</span>
                  </a>
                ))}
              </div>
            </div>

            <div className="md:col-span-2 flex flex-col gap-3">
              <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 uppercase tracking-wider">Architecture</span>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#history">Historical Roots</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#product">Robotic Arm</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#product">Vision Overlay</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#features">Grandmaster Engine</a>
            </div>

            <div className="md:col-span-2 flex flex-col gap-3">
              <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 uppercase tracking-wider">Ecosystem</span>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#how-it-works">Calibration</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#why-robochess">The Community</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#">API Documentation</a>
              <a className="text-xs hover:text-[var(--color-primary)] transition-colors" href="#">Firmware Updates</a>
            </div>

            <div className="md:col-span-3 flex flex-col gap-4">
              <span className="font-[var(--font-headline)] text-sm font-bold text-slate-900 uppercase tracking-wider">Mobile Controller</span>
              <p className="text-xs text-slate-500">Command the robotic physical board via BLE 5.4 telemetry.</p>
              <div className="flex flex-col gap-2">
                <a href="https://github.com/rayyanshaikh123/robochess" target="_blank" rel="noopener noreferrer" className="flex items-center gap-3 px-4 py-2.5 rounded-xl bg-white border border-[var(--color-outline)] hover:border-slate-300 text-slate-800 transition-all shadow-sm">
                  <span className="material-symbols-outlined text-[var(--color-primary)] text-[20px]">phone_iphone</span>
                  <div className="flex flex-col text-left">
                    <span className="text-[9px] text-slate-400 uppercase leading-none font-semibold">Download on</span>
                    <span className="font-[var(--font-headline)] text-xs font-bold leading-tight">Apple App Store</span>
                  </div>
                </a>
                <a href="https://github.com/rayyanshaikh123/robochess" target="_blank" rel="noopener noreferrer" className="flex items-center gap-3 px-4 py-2.5 rounded-xl bg-white border border-[var(--color-outline)] hover:border-slate-300 text-slate-800 transition-all shadow-sm">
                  <span className="material-symbols-outlined text-[var(--color-primary)] text-[20px]">android</span>
                  <div className="flex flex-col text-left">
                    <span className="text-[9px] text-slate-400 uppercase leading-none font-semibold">Get it on</span>
                    <span className="font-[var(--font-headline)] text-xs font-bold leading-tight">Google Play</span>
                  </div>
                </a>
              </div>
            </div>
          </div>

          <div className="mt-12 pt-6 border-t border-slate-200 flex flex-col md:flex-row items-center justify-between gap-4">
            <p className="text-xs text-slate-500">&copy; {new Date().getFullYear()} RoboChess. All rights reserved.</p>
            <div className="flex items-center gap-6">
              <a className="text-xs text-slate-500 hover:text-slate-900 transition-colors" href="#">Privacy Policy</a>
              <a className="text-xs text-slate-500 hover:text-slate-900 transition-colors" href="#">Terms of Service</a>
              <a className="text-xs text-slate-500 hover:text-slate-900 transition-colors" href="#">Robotic Safety</a>
            </div>
          </div>
        </div>
      </footer>
    </>
  );
}

import Image from "next/image";
import AppTour from "./components/AppTour";
import HeroScrub from "./components/HeroScrub";
import MotionRoot from "./components/MotionRoot";
import { Icon } from "./components/Icons";
import type { CSSProperties } from "react";

const REPO = "https://github.com/rayyanshaikh123/robochess";
const APK = process.env.NEXT_PUBLIC_APK_URL || "/downloads/robochess.apk";
const APK_META = "APK 54 MB, version 1.0.0";

const NAV = [
  { href: "#limbs", label: "Four limbs" },
  { href: "#timeline", label: "The long game" },
  { href: "#pipeline", label: "How it sees" },
  { href: "#app", label: "The app" },
  { href: "#features", label: "What it does" },
  { href: "#answers", label: "Answers" },
];

const LIMBS = [
  {
    sanskrit: "Padati",
    ancient: "the infantry",
    piece: "now the pawn",
    icon: "pawn" as const,
    part: "The sixty four squares",
    body: "Foot soldiers held the line one square at a time. Our line is the board itself, every square watched frame by frame while the game runs.",
  },
  {
    sanskrit: "Ashva",
    ancient: "the cavalry",
    piece: "now the knight",
    icon: "knight" as const,
    part: "The engine",
    body: "The horse was the piece that could leave the line. Stockfish is ours, jumping through positions faster than anyone at the table has patience to count.",
  },
  {
    sanskrit: "Gaja",
    ancient: "the war elephants",
    piece: "now the bishop",
    icon: "bishop" as const,
    part: "The eye",
    body: "Elephants saw over the field and told the army what was there. A camera and a trained model do that job now, turning a photo of your board into a position.",
  },
  {
    sanskrit: "Ratha",
    ancient: "the chariots",
    piece: "now the rook",
    icon: "rook" as const,
    part: "The link",
    body: "Chariots carried word across the field. Bluetooth and websockets carry yours, from the board to the phone to the server and back again.",
  },
];

const STOPS = [
  {
    when: "c. 6th century",
    where: "India",
    title: "Chaturanga",
    body: "Four limbs of an army on the ashtapada, an eight by eight grid people were already playing other games on.",
  },
  {
    when: "7th century",
    where: "Persia",
    title: "Shatranj",
    body: "The same army with new names. The Persian phrase for the cornered king is where the word checkmate comes from.",
  },
  {
    when: "around 1475",
    where: "Southern Europe",
    title: "The queen is set free",
    body: "The counsellor became the queen and took the long diagonals with her. Games got sharper, and the modern rules settled around her.",
  },
  {
    when: "1997",
    where: "New York",
    title: "Deep Blue",
    body: "A machine won a match against the reigning world champion. The argument about whether computers could play was over.",
  },
  {
    when: "2017",
    where: "London",
    title: "AlphaZero",
    body: "A program was given the rules and nothing else, played itself for hours, and came out playing like nothing before it.",
  },
  {
    when: "Now",
    where: "Your table",
    title: "RoboChess",
    body: "The wood stays. The board joins the network, reads its own position, and hands it to the engine.",
  },
];

const PIPELINE = [
  {
    icon: "eye" as const,
    title: "The camera looks",
    body: "A phone camera or a webcam over the board sends frames in while you play.",
  },
  {
    icon: "squares" as const,
    title: "The model finds the squares",
    body: "OpenCV squares the board up and a trained detector labels what is standing on it.",
  },
  {
    icon: "cpu" as const,
    title: "The position becomes text",
    body: "python-chess turns that grid into a FEN string, the notation every chess program already speaks.",
  },
  {
    icon: "graph" as const,
    title: "The engine answers",
    body: "Stockfish reads the position and sends back its evaluation and the line it likes.",
  },
  {
    icon: "link" as const,
    title: "Everything stays in step",
    body: "FastAPI holds the game, MongoDB keeps it, and websockets and Bluetooth keep the app and the board on the same move.",
  },
];

const FEATURES = [
  {
    icon: "cpu" as const,
    title: "Play the engine",
    body: "Stockfish on the other side of the board, at the strength you pick.",
  },
  {
    icon: "people" as const,
    title: "Play a friend",
    body: "Send a challenge, or take a game against whoever is online.",
  },
  {
    icon: "puzzle" as const,
    title: "Solve puzzles",
    body: "A puzzle library with your progress kept against your account.",
  },
  {
    icon: "graph" as const,
    title: "Go back over a game",
    body: "Walk a finished game move by move with the engine's read on each one.",
  },
  {
    icon: "voice" as const,
    title: "Speak a move",
    body: "Say it out loud when both hands are busy on the pieces.",
  },
  {
    icon: "link" as const,
    title: "Pair a board",
    body: "Find a RoboChess board over Bluetooth and link it to your account.",
  },
  {
    icon: "offline" as const,
    title: "Keep playing offline",
    body: "The Raspberry Pi runs the game with no network and syncs the session when the connection returns.",
  },
  {
    icon: "squares" as const,
    title: "Set a board up",
    body: "Calibrate a physical board once and check that every square reads correctly.",
  },
];

const ANSWERS = [
  {
    q: "Do I need the hardware to try this?",
    a: "No. The app plays on its own. The physical board is the part that reads real pieces, and everything else works without it.",
  },
  {
    q: "What happens when the internet drops?",
    a: "The Raspberry Pi holds the game locally and keeps playing. When the connection comes back it sends the session up to the server.",
  },
  {
    q: "Is my camera good enough?",
    a: "A normal phone camera or a webcam is enough. Even light across the board matters more than the sensor does.",
  },
  {
    q: "Is the project finished?",
    a: "No, and the page is not going to pretend otherwise. It runs today and it is still being built. The camera and board parts need setting up on your own hardware.",
  },
  {
    q: "Can I read the code?",
    a: "Yes. The Flutter app, the FastAPI server and the Pi agent all sit in one public repository.",
  },
  {
    q: "Where do my games live?",
    a: "In MongoDB, on the server you run. Point the backend at your own database and the games stay with you.",
  },
];

function BrandMark({ size = 34 }: { size?: number }) {
  return (
    <Image
      className="brand-mark"
      src="/app_logo.png"
      alt=""
      width={size}
      height={size}
      priority
      aria-hidden="true"
    />
  );
}

export default function Home() {
  const year = new Date().getFullYear();

  return (
    <>
      <MotionRoot />
      <a className="skip-link" href="#main">
        Skip to content
      </a>

      <header className="site-header">
        <div className="shell header-inner">
          <a className="brand" href="#top">
            <BrandMark />
            <span>RoboChess</span>
          </a>

          <nav className="site-nav" aria-label="Sections">
            {NAV.map((item) => (
              <a key={item.href} href={item.href}>
                {item.label}
              </a>
            ))}
          </nav>

          <a className="btn btn-solid header-cta" href="/app/">
            Open the board
          </a>
        </div>
      </header>

      <main id="main" tabIndex={-1}>
        <div id="top" />
        <HeroScrub />

        {/* ── The four limbs: the culture section and the site's device ── */}
        <section id="limbs" className="band-section limbs-section">
          <div className="shell">
            <div className="limbs-intro">
              <div className="reveal">
                <p className="kicker">Chaturanga, the four limbs</p>
                <h2 className="section-title">
                  The oldest name for the game is a headcount.
                </h2>
              </div>
              <div className="reveal" style={{ "--i": 1 } as CSSProperties}>
                <p className="lede">
                  Chaturanga means four limbs, the four parts of an old Indian army: foot soldiers,
                  horses, elephants and chariots. Every piece on a modern board is one of them,
                  worn down by fifteen centuries of translation. RoboChess is built in four parts
                  too, and they line up better than we expected.
                </p>
              </div>
            </div>

            <ol className="limbs-grid">
              {LIMBS.map((limb, i) => (
                <li
                  key={limb.sanskrit}
                  className="limb panel panel-lift reveal"
                  style={{ "--i": i } as CSSProperties}
                >
                  <div className="limb-head">
                    <Icon name={limb.icon} size={40} className="limb-glyph" />
                    <div>
                      <p className="limb-name">{limb.sanskrit}</p>
                      <p className="limb-role">{limb.ancient}</p>
                      <p className="limb-became">{limb.piece}</p>
                    </div>
                  </div>
                  <h3 className="limb-part">{limb.part}</h3>
                  <p className="limb-body">{limb.body}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* ── The long game: a drawn rail from the ashtapada to now ── */}
        <section id="timeline" className="band-section timeline-section">
          <div className="shell">
            <div className="timeline-head">
              <p className="kicker reveal">The long game</p>
              <h2 className="section-title reveal" style={{ "--i": 1 } as CSSProperties}>
                Fifteen centuries, one grid.
              </h2>
              <p className="lede reveal" style={{ "--i": 2 } as CSSProperties}>
                The board has barely changed. Everything around it has changed constantly, and
                each change arrived the same way: someone gave the game a new surface to live on.
              </p>
            </div>

            <svg className="rail-line" viewBox="0 0 1000 2" preserveAspectRatio="none" aria-hidden="true">
              <path
                data-draw=""
                className="draw"
                d="M0 1 H1000"
                stroke="var(--rule-strong)"
                strokeWidth="2"
                fill="none"
              />
            </svg>

            <ol className="rail">
              {STOPS.map((stop, i) => (
                <li key={stop.title} className="stop reveal" style={{ "--i": i } as CSSProperties}>
                  <span className="stop-node" aria-hidden="true" />
                  <p className="stop-when">
                    {stop.when}
                    <span className="stop-where">{stop.where}</span>
                  </p>
                  <h3 className="stop-title">{stop.title}</h3>
                  <p className="stop-body">{stop.body}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* ── How the board sees ── */}
        <section id="pipeline" className="band-section pipeline-section">
          <div className="shell">
            <div className="pipeline-head">
              <p className="kicker reveal pipeline-kicker">Look. Read. Answer.</p>
              <h2 className="section-title reveal" style={{ "--i": 1 } as CSSProperties}>
                How a wooden board tells you what is on it.
              </h2>
              <p className="lede pipeline-lede reveal" style={{ "--i": 2 } as CSSProperties}>
                Five steps run between the piece leaving your hand and the move showing up on your
                phone. None of them ask you to type anything.
              </p>
            </div>

            <div className="pipeline-rail" aria-hidden="true">
              <span className="pipeline-track" />
              <span className="pipeline-dot" style={{ "--d": "0s" } as CSSProperties} />
              <span className="pipeline-dot" style={{ "--d": "-1.8s" } as CSSProperties} />
              <span className="pipeline-dot" style={{ "--d": "-3.6s" } as CSSProperties} />
            </div>

            <ol className="pipeline-steps">
              {PIPELINE.map((step, i) => (
                <li key={step.title} className="pipe-step reveal" style={{ "--i": i } as CSSProperties}>
                  <span className="pipe-index">{String(i + 1).padStart(2, "0")}</span>
                  <Icon name={step.icon} size={26} className="pipe-icon" />
                  <h3 className="pipe-title">{step.title}</h3>
                  <p className="pipe-body">{step.body}</p>
                </li>
              ))}
            </ol>

            <p className="pipeline-stack reveal" style={{ "--i": 5 } as CSSProperties}>
              <span>Flutter</span>
              <span>FastAPI</span>
              <span>MongoDB</span>
              <span>OpenCV</span>
              <span>Stockfish</span>
              <span>Raspberry Pi</span>
              <span>Bluetooth LE</span>
            </p>
          </div>
        </section>

        {/* ── Inside the app ── */}
        <section id="app" className="band-section tour-section">
          <div className="shell">
            <div className="tour-head">
              <p className="kicker reveal">Inside the app</p>
              <h2 className="section-title reveal" style={{ "--i": 1 } as CSSProperties}>
                Six tabs, one game.
              </h2>
              <p className="lede reveal" style={{ "--i": 2 } as CSSProperties}>
                The same account follows you from the phone to the board and back. Here is what sits
                behind each tab.
              </p>
            </div>

          </div>

          {/* full width: the arc needs the whole stage, not the text column.
              The download rides inside the stage and arrives with the last
              screen, so it reads as the payoff instead of turning up late. */}
          <AppTour
            footer={
              <>
                <a className="btn btn-solid" href={APK} download>
                  <Icon name="android" size={18} />
                  Download for Android
                </a>
                <span className="chip">{APK_META}</span>
                <a className="btn btn-quiet" href="/app/">
                  Open in the browser
                </a>
              </>
            }
          />
        </section>

        {/* ── What you can do with it ── */}
        <section id="features" className="band-section features-section">
          <div className="shell">
            <div className="features-head">
              <div className="reveal">
                <p className="kicker">In the app today</p>
                <h2 className="section-title">Eight things it already does.</h2>
              </div>
              <a className="btn btn-quiet reveal" style={{ "--i": 1 } as CSSProperties} href="/app/">
                Open the board
                <Icon name="arrow" size={18} />
              </a>
            </div>

            <ul className="feature-list">
              {FEATURES.map((feature, i) => (
                <li key={feature.title} className="feature reveal" style={{ "--i": i % 4 } as CSSProperties}>
                  <Icon name={feature.icon} size={22} className="feature-icon" />
                  <div>
                    <h3 className="feature-title">{feature.title}</h3>
                    <p className="feature-body">{feature.body}</p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* ── Straight answers ── */}
        <section id="answers" className="band-section answers-section">
          <div className="shell answers-grid">
            <div className="answers-head">
              <p className="kicker reveal">Straight answers</p>
              <h2 className="section-title reveal" style={{ "--i": 1 } as CSSProperties}>
                The questions people actually ask.
              </h2>
              <p className="lede reveal" style={{ "--i": 2 } as CSSProperties}>
                Nothing here is a sales answer. If something is unfinished, it says so.
              </p>
            </div>

            <div className="answers-list">
              {ANSWERS.map((item, i) => (
                <details
                  key={item.q}
                  className="answer reveal"
                  open={i === 0}
                  style={{ "--i": i } as CSSProperties}
                >
                  <summary>
                    <span>{item.q}</span>
                    <span className="answer-mark" aria-hidden="true" />
                  </summary>
                  <p>{item.a}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        {/* ── The one call to action ── */}
        <section id="open" className="band-section closing-section">
          <div className="shell closing">
            <div className="closing-lattice" aria-hidden="true">
              {Array.from({ length: 64 }, (_, i) => (
                <span
                  key={i}
                  data-dark={((i % 8) + Math.floor(i / 8)) % 2 === 0 ? "" : undefined}
                  style={{ "--i": i % 8 } as CSSProperties}
                />
              ))}
            </div>
            <p className="kicker reveal">The board is open</p>
            <h2 className="closing-title reveal" style={{ "--i": 1 } as CSSProperties}>
              Sixty four squares are waiting.
            </h2>
            <p className="lede closing-lede reveal" style={{ "--i": 2 } as CSSProperties}>
              Play a game in the browser right now. Bring a real board to it whenever you are
              ready.
            </p>
            <div className="closing-actions reveal" style={{ "--i": 3 } as CSSProperties}>
              <a className="btn btn-solid" href="/app/">
                <Icon name="play" size={18} />
                Open the board
              </a>
              <a className="btn btn-quiet" href={APK} download>
                <Icon name="android" size={18} />
                Android APK
              </a>
              <a className="btn btn-quiet" href={REPO} rel="noreferrer noopener" target="_blank">
                <Icon name="github" size={18} />
                Read the code
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell footer-inner">
          <div className="footer-brand">
            <BrandMark size={30} />
            <div>
              <p className="footer-name">RoboChess</p>
              <p className="footer-note">
                A connected chessboard, built in the open and still being built.
              </p>
            </div>
          </div>

          <nav className="footer-nav" aria-label="Footer">
            <a href="/app/">Open the board</a>
            <a href={APK} download>
              Android APK
            </a>
            <a href={REPO} rel="noreferrer noopener" target="_blank">
              Source on GitHub
            </a>
            <a href="#limbs">Four limbs</a>
            <a href="#answers">Answers</a>
          </nav>

          <p className="footer-legal">
            <span>{year} RoboChess</span>
            <span className="footer-rule" aria-hidden="true" />
            <span>Chess pieces have travelled further than most of us.</span>
          </p>
        </div>
      </footer>
    </>
  );
}

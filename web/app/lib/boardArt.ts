/**
 * The Board of Ages.
 *
 * One 8x8 board in true perspective, drawn frame by frame, aged from a grid
 * scratched into sand into a board that reports its own position. Scroll
 * progress (0..1) is the only thing that moves it, so the journey reverses
 * exactly on the way back up. Nothing here is an image or a video.
 *
 * Eras, in progress units:
 *   0.00 .. 0.20  the ashtapada, drawn on the ground
 *   0.18 .. 0.42  the checker pattern inks in, sand warms into wood
 *   0.40 .. 0.62  a sweep of light crosses and the pieces become the modern set
 *   0.58 .. 0.85  the sensor lattice ignites, brackets lock on
 *   0.82 .. 1.00  everything rests
 */

export type Vec = { x: number; y: number };

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Eased 0..1 ramp between two progress marks. */
const seg = (p: number, a: number, b: number) => {
  const t = clamp01((p - a) / (b - a));
  return t * t * (3 - 2 * t);
};

const rgba = (hex: string, alpha: number) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
};

const mix = (a: string, b: string, t: number) => {
  const x = parseInt(a.slice(1), 16);
  const y = parseInt(b.slice(1), 16);
  const r = Math.round(lerp((x >> 16) & 255, (y >> 16) & 255, t));
  const g = Math.round(lerp((x >> 8) & 255, (y >> 8) & 255, t));
  const bl = Math.round(lerp(x & 255, y & 255, t));
  return `rgb(${r}, ${g}, ${bl})`;
};

/* ── The palette, the same tokens the page uses ──────────────────────── */

const SAND = "#d9c7a3";
const SAND_LINE = "#b49a70";
const WOOD_LIGHT = "#e9d5b0";
const WOOD_DARK = "#a9784f";
const FRAME = "#7d5635";
const INK = "#16211c";
const SIGNAL = "#0e9f8e";

const STONE_LIGHT = "#bda380";
const STONE_DARK = "#7c6349";
const BOXWOOD = "#f3e6cc";
const WALNUT = "#3b2b1f";

/* ── The army: chaturanga and modern chess share this back rank ──────── */

const BACK_RANK = ["r", "n", "b", "q", "k", "b", "n", "r"] as const;
type PieceKind = (typeof BACK_RANK)[number] | "p";

type Man = { file: number; rank: number; kind: PieceKind; light: boolean };

const ARMY: Man[] = (() => {
  const out: Man[] = [];
  for (let f = 0; f < 8; f++) {
    out.push({ file: f, rank: 0, kind: BACK_RANK[f], light: false });
    out.push({ file: f, rank: 1, kind: "p", light: false });
    out.push({ file: f, rank: 6, kind: "p", light: true });
    out.push({ file: f, rank: 7, kind: BACK_RANK[f], light: true });
  }
  return out;
})();

/* ── Seeded ambient life, identical on every load ─────────────────────── */

const rng = (seed: number) => {
  let s = seed >>> 0;
  return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
};

const MOTES = (() => {
  const r = rng(0x5eed1);
  return Array.from({ length: 30 }, () => ({
    x: r(),
    y: r(),
    size: 0.6 + r() * 1.7,
    speed: 0.1 + r() * 0.28,
    phase: r() * Math.PI * 2,
    sway: 0.008 + r() * 0.03,
  }));
})();

/* ── Perspective ─────────────────────────────────────────────────────── */

type Camera = {
  cx: number;
  cy: number;
  boardW: number;
  boardH: number;
  persp: number;
  horizon: number;
  amp: number;
};

function makeCamera(w: number, h: number, p: number, compact: boolean): Camera {
  const persp = lerp(0.34, 0.46, seg(p, 0, 1));
  const fit = compact ? Math.min(w * 0.92, h * 1.9) : Math.min(w * 0.5, h * 0.92);
  const boardW = fit * lerp(0.9, 1.0, seg(p, 0.1, 0.95));
  const boardH = boardW * 0.6;
  const cy = h * (compact ? 0.52 : lerp(0.66, 0.685, seg(p, 0, 1)));
  const near = cy + boardH / 2;
  const amp = (boardH * (1 + persp)) / persp;
  return { cx: w / 2, cy, boardW, boardH, persp, horizon: near - amp, amp };
}

/** u: 0 left to 1 right. v: 0 far edge to 1 near edge. */
function project(cam: Camera, u: number, v: number): Vec {
  const s = 1 / (1 + cam.persp * (1 - v));
  return { x: cam.cx + (u - 0.5) * cam.boardW * s, y: cam.horizon + cam.amp * s };
}

const depthScale = (cam: Camera, v: number) => 1 / (1 + cam.persp * (1 - v));

function squareQuad(cam: Camera, file: number, rank: number) {
  const u0 = file / 8;
  const u1 = (file + 1) / 8;
  const v0 = rank / 8;
  const v1 = (rank + 1) / 8;
  return [project(cam, u0, v0), project(cam, u1, v0), project(cam, u1, v1), project(cam, u0, v1)];
}

function quadPath(ctx: CanvasRenderingContext2D, q: Vec[]) {
  ctx.beginPath();
  ctx.moveTo(q[0].x, q[0].y);
  for (let i = 1; i < q.length; i++) ctx.lineTo(q[i].x, q[i].y);
  ctx.closePath();
}

/* ── Piece silhouettes, drawn in a unit box ───────────────────────────
   x from -0.5 to 0.5, y from -1 (crown) to 0 (the square it stands on).  */

function base(ctx: CanvasRenderingContext2D, w: number, hgt: number) {
  ctx.beginPath();
  ctx.moveTo(-w, 0);
  ctx.lineTo(w, 0);
  ctx.lineTo(w * 0.78, -hgt);
  ctx.lineTo(-w * 0.78, -hgt);
  ctx.closePath();
  ctx.fill();
}

function body(ctx: CanvasRenderingContext2D, bw: number, tw: number, y0: number, y1: number) {
  ctx.beginPath();
  ctx.moveTo(-bw, y0);
  ctx.quadraticCurveTo(-tw * 1.35, (y0 + y1) / 2, -tw, y1);
  ctx.lineTo(tw, y1);
  ctx.quadraticCurveTo(tw * 1.35, (y0 + y1) / 2, bw, y0);
  ctx.closePath();
  ctx.fill();
}

function ball(ctx: CanvasRenderingContext2D, y: number, r: number) {
  ctx.beginPath();
  ctx.arc(0, y, r, 0, Math.PI * 2);
  ctx.fill();
}

const MODERN: Record<PieceKind, (ctx: CanvasRenderingContext2D) => void> = {
  p: (ctx) => {
    base(ctx, 0.3, 0.08);
    body(ctx, 0.19, 0.11, -0.07, -0.42);
    ctx.fillRect(-0.21, -0.47, 0.42, 0.06);
    ball(ctx, -0.6, 0.15);
  },
  r: (ctx) => {
    base(ctx, 0.33, 0.09);
    body(ctx, 0.24, 0.21, -0.08, -0.52);
    ctx.fillRect(-0.3, -0.64, 0.6, 0.13);
    ctx.fillRect(-0.3, -0.78, 0.17, 0.15);
    ctx.fillRect(-0.085, -0.78, 0.17, 0.15);
    ctx.fillRect(0.13, -0.78, 0.17, 0.15);
  },
  n: (ctx) => {
    base(ctx, 0.32, 0.09);
    ctx.beginPath();
    ctx.moveTo(-0.22, -0.08);
    ctx.lineTo(0.22, -0.08);
    ctx.lineTo(0.2, -0.36);
    ctx.lineTo(0.3, -0.62);
    ctx.lineTo(0.12, -0.83);
    ctx.lineTo(-0.06, -0.9);
    ctx.lineTo(-0.16, -0.76);
    ctx.lineTo(-0.3, -0.66);
    ctx.lineTo(-0.24, -0.5);
    ctx.lineTo(-0.1, -0.44);
    ctx.lineTo(-0.16, -0.3);
    ctx.closePath();
    ctx.fill();
  },
  b: (ctx) => {
    base(ctx, 0.3, 0.08);
    body(ctx, 0.2, 0.12, -0.07, -0.46);
    ctx.beginPath();
    ctx.moveTo(-0.16, -0.46);
    ctx.quadraticCurveTo(-0.19, -0.72, 0, -0.88);
    ctx.quadraticCurveTo(0.19, -0.72, 0.16, -0.46);
    ctx.closePath();
    ctx.fill();
    ball(ctx, -0.93, 0.055);
  },
  q: (ctx) => {
    base(ctx, 0.35, 0.09);
    body(ctx, 0.24, 0.15, -0.08, -0.55);
    ctx.beginPath();
    ctx.moveTo(-0.26, -0.55);
    ctx.lineTo(-0.3, -0.84);
    ctx.lineTo(-0.15, -0.7);
    ctx.lineTo(0, -0.88);
    ctx.lineTo(0.15, -0.7);
    ctx.lineTo(0.3, -0.84);
    ctx.lineTo(0.26, -0.55);
    ctx.closePath();
    ctx.fill();
    ball(ctx, -0.92, 0.06);
  },
  k: (ctx) => {
    base(ctx, 0.35, 0.09);
    body(ctx, 0.25, 0.16, -0.08, -0.58);
    ctx.beginPath();
    ctx.moveTo(-0.27, -0.58);
    ctx.lineTo(-0.23, -0.8);
    ctx.lineTo(0.23, -0.8);
    ctx.lineTo(0.27, -0.58);
    ctx.closePath();
    ctx.fill();
    ctx.fillRect(-0.05, -1.0, 0.1, 0.22);
    ctx.fillRect(-0.14, -0.94, 0.28, 0.08);
  },
};

const ANCIENT: Record<PieceKind, (ctx: CanvasRenderingContext2D) => void> = {
  // padati, the foot soldier
  p: (ctx) => {
    base(ctx, 0.26, 0.07);
    ctx.beginPath();
    ctx.moveTo(-0.17, -0.06);
    ctx.quadraticCurveTo(-0.16, -0.46, 0, -0.5);
    ctx.quadraticCurveTo(0.16, -0.46, 0.17, -0.06);
    ctx.closePath();
    ctx.fill();
  },
  // ratha, the chariot
  r: (ctx) => {
    base(ctx, 0.32, 0.08);
    // the car and its wheel, cut as one even-odd path so the hub reads through
    ctx.beginPath();
    ctx.rect(-0.26, -0.58, 0.52, 0.51);
    ctx.moveTo(0.16, -0.32);
    ctx.arc(0, -0.32, 0.16, 0, Math.PI * 2);
    ctx.moveTo(0.055, -0.32);
    ctx.arc(0, -0.32, 0.055, 0, Math.PI * 2);
    ctx.fill("evenodd");
  },
  // ashva, the horse
  n: (ctx) => {
    base(ctx, 0.3, 0.08);
    ctx.beginPath();
    ctx.moveTo(-0.2, -0.07);
    ctx.lineTo(0.2, -0.07);
    ctx.lineTo(0.22, -0.48);
    ctx.lineTo(0.05, -0.72);
    ctx.lineTo(-0.1, -0.66);
    ctx.lineTo(-0.22, -0.48);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-0.02, -0.7);
    ctx.lineTo(0.06, -0.86);
    ctx.lineTo(0.13, -0.68);
    ctx.closePath();
    ctx.fill();
  },
  // gaja, the war elephant
  b: (ctx) => {
    base(ctx, 0.3, 0.08);
    ctx.beginPath();
    ctx.moveTo(-0.25, -0.07);
    ctx.quadraticCurveTo(-0.26, -0.56, 0, -0.62);
    ctx.quadraticCurveTo(0.26, -0.56, 0.25, -0.07);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-0.2, -0.4);
    ctx.quadraticCurveTo(-0.34, -0.5, -0.29, -0.62);
    ctx.lineTo(-0.22, -0.55);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(0.2, -0.4);
    ctx.quadraticCurveTo(0.34, -0.5, 0.29, -0.62);
    ctx.lineTo(0.22, -0.55);
    ctx.closePath();
    ctx.fill();
  },
  // mantri, the counsellor who later became the queen
  q: (ctx) => {
    base(ctx, 0.3, 0.08);
    ctx.beginPath();
    ctx.moveTo(-0.2, -0.07);
    ctx.quadraticCurveTo(-0.21, -0.58, 0, -0.66);
    ctx.quadraticCurveTo(0.21, -0.58, 0.2, -0.07);
    ctx.closePath();
    ctx.fill();
    ctx.fillRect(-0.05, -0.78, 0.1, 0.14);
  },
  // raja, the king
  k: (ctx) => {
    base(ctx, 0.32, 0.08);
    ctx.beginPath();
    ctx.moveTo(-0.22, -0.07);
    ctx.quadraticCurveTo(-0.24, -0.66, 0, -0.76);
    ctx.quadraticCurveTo(0.24, -0.66, 0.22, -0.07);
    ctx.closePath();
    ctx.fill();
    ctx.fillRect(-0.15, -0.84, 0.3, 0.07);
    ball(ctx, -0.92, 0.075);
  },
};

/* ── The ashtapada's marked squares ──────────────────────────────────── */

const MARKED: Array<[number, number]> = [
  [0, 0],
  [7, 0],
  [0, 7],
  [7, 7],
  [3, 3],
  [4, 3],
  [3, 4],
  [4, 4],
];

/* ── The frame ───────────────────────────────────────────────────────── */

export type DrawOpts = {
  width: number;
  height: number;
  progress: number;
  time: number;
  compact?: boolean;
};

export function drawBoardOfAges(ctx: CanvasRenderingContext2D, opts: DrawOpts) {
  const { width: w, height: h, progress: p, time } = opts;
  const compact = opts.compact ?? false;
  const cam = makeCamera(w, h, p, compact);

  ctx.clearRect(0, 0, w, h);

  const scratch = 0.2 + 0.8 * seg(p, 0.0, 0.1); // the grid being drawn on the ground
  const ink = seg(p, 0.18, 0.42); // the checker pattern arriving
  const sweep = seg(p, 0.4, 0.62); // the light crossing, the pieces changing
  const lattice = seg(p, 0.58, 0.85); // the sensors waking
  const rest = seg(p, 0.82, 1.0); // the arrival

  drawGround(ctx, cam, w, h, ink, rest);
  drawSquares(ctx, cam, ink, scratch, lattice);
  drawMarks(ctx, cam, scratch, ink);
  drawGrid(ctx, cam, scratch, ink);
  drawPieces(ctx, cam, sweep, ink);
  drawSweep(ctx, cam, w, h, p);
  drawLattice(ctx, cam, lattice, time);
  drawBrackets(ctx, cam, lattice);
  drawCoords(ctx, cam, lattice);
  drawMotes(ctx, cam, w, h, p, time);
  drawRest(ctx, cam, rest);
}

/* The table the board sits on, and the glow it earns at the end. */
function drawGround(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  w: number,
  h: number,
  ink: number,
  rest: number,
) {
  const near = project(cam, 0.5, 1).y;
  const far = project(cam, 0.5, 0).y;

  const ground = ctx.createLinearGradient(0, far - cam.boardH * 0.5, 0, near + cam.boardH * 0.6);
  ground.addColorStop(0, rgba(SAND, 0.0));
  ground.addColorStop(0.45, rgba(SAND, 0.22 + 0.1 * ink));
  ground.addColorStop(1, rgba(SAND_LINE, 0.12));
  ctx.fillStyle = ground;
  ctx.fillRect(0, far - cam.boardH, w, h - (far - cam.boardH));

  // The wooden frame grows in as the board becomes an object rather than a drawing.
  if (ink > 0.01) {
    const pad = 0.055;
    const q = [
      project(cam, -pad, -pad * 0.9),
      project(cam, 1 + pad, -pad * 0.9),
      project(cam, 1 + pad, 1 + pad * 0.6),
      project(cam, -pad, 1 + pad * 0.6),
    ];
    ctx.save();
    ctx.globalAlpha = ink;
    ctx.shadowColor = rgba(INK, 0.22);
    ctx.shadowBlur = 42 * ink;
    ctx.shadowOffsetY = 18 * ink;
    quadPath(ctx, q);
    ctx.fillStyle = mix(SAND_LINE, FRAME, ink);
    ctx.fill();
    ctx.restore();
  }

  if (rest > 0.01) {
    const glow = ctx.createRadialGradient(cam.cx, near, 0, cam.cx, near, cam.boardW * 0.62);
    glow.addColorStop(0, rgba(SIGNAL, 0.16 * rest));
    glow.addColorStop(1, rgba(SIGNAL, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(cam.cx - cam.boardW, near - cam.boardH, cam.boardW * 2, cam.boardH * 2);
  }
}

function drawSquares(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  ink: number,
  scratch: number,
  lattice: number,
) {
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const q = squareQuad(cam, f, r);
      quadPath(ctx, q);

      // The sand ground is there from the first frame.
      ctx.fillStyle = SAND;
      ctx.globalAlpha = 0.72 + 0.28 * scratch;
      ctx.fill();

      // The checker pattern inks in on a diagonal sweep, one square at a time.
      const order = (f + r) / 14;
      const a = clamp01((ink - order * 0.62) * 3.4);
      if (a > 0.004) {
        const dark = (f + r) % 2 === 1;
        ctx.globalAlpha = a;
        ctx.fillStyle = dark ? WOOD_DARK : WOOD_LIGHT;
        ctx.fill();
        if (lattice > 0.02) {
          ctx.globalAlpha = a * lattice * (dark ? 0.09 : 0.045);
          ctx.fillStyle = SIGNAL;
          ctx.fill();
        }
      }
      ctx.globalAlpha = 1;
    }
  }
}

/* The crosses the ashtapada carried before chess was played on it. */
function drawMarks(ctx: CanvasRenderingContext2D, cam: Camera, scratch: number, ink: number) {
  const a = scratch * (1 - ink);
  if (a < 0.01) return;
  ctx.save();
  ctx.globalAlpha = a * 0.55;
  ctx.strokeStyle = SAND_LINE;
  ctx.lineCap = "round";
  for (const [f, r] of MARKED) {
    const c = project(cam, (f + 0.5) / 8, (r + 0.5) / 8);
    const s = (cam.boardW / 8) * depthScale(cam, (r + 0.5) / 8) * 0.22;
    ctx.lineWidth = Math.max(1, s * 0.22);
    ctx.beginPath();
    ctx.moveTo(c.x - s, c.y - s * 0.55);
    ctx.lineTo(c.x + s, c.y + s * 0.55);
    ctx.moveTo(c.x + s, c.y - s * 0.55);
    ctx.lineTo(c.x - s, c.y + s * 0.55);
    ctx.stroke();
  }
  ctx.restore();
}

/* The grid itself, scratched in line by line at the very start. */
function drawGrid(ctx: CanvasRenderingContext2D, cam: Camera, scratch: number, ink: number) {
  ctx.save();
  ctx.strokeStyle = mix(SAND_LINE, FRAME, ink);
  ctx.globalAlpha = 0.5 - 0.22 * ink;
  ctx.lineCap = "round";

  for (let i = 0; i <= 8; i++) {
    const t = clamp01((scratch - (i / 8) * 0.55) * 3.2);
    if (t < 0.01) continue;
    ctx.lineWidth = Math.max(0.8, cam.boardW * 0.0016);

    // lines running away from the viewer
    const a = project(cam, i / 8, 0);
    const b = project(cam, i / 8, 1);
    ctx.beginPath();
    ctx.moveTo(b.x, b.y);
    ctx.lineTo(lerp(b.x, a.x, t), lerp(b.y, a.y, t));
    ctx.stroke();

    // lines running across
    const c = project(cam, 0, i / 8);
    const d = project(cam, 1, i / 8);
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.lineTo(lerp(c.x, d.x, t), lerp(c.y, d.y, t));
    ctx.stroke();
  }
  ctx.restore();
}

function drawPieces(ctx: CanvasRenderingContext2D, cam: Camera, sweep: number, ink: number) {
  const lightCol = mix(STONE_LIGHT, BOXWOOD, ink);
  const darkCol = mix(STONE_DARK, WALNUT, ink);

  for (let r = 0; r < 8; r++) {
    for (const man of ARMY) {
      if (man.rank !== r) continue;
      const v = (man.rank + 0.62) / 8;
      const u = (man.file + 0.5) / 8;
      const at = project(cam, u, v);
      const s = (cam.boardW / 8) * depthScale(cam, v);
      const size = s * 1.05;

      // the shadow the piece casts on its square
      ctx.save();
      ctx.globalAlpha = 0.1 + 0.07 * ink;
      ctx.fillStyle = INK;
      ctx.beginPath();
      ctx.ellipse(at.x, at.y + s * 0.03, s * 0.26, s * 0.085, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();

      ctx.save();
      ctx.translate(at.x, at.y);
      ctx.scale(size, size);
      ctx.fillStyle = man.light ? lightCol : darkCol;

      // The two sets cross under the sweep of light, so the swap never shows.
      if (sweep < 0.995) {
        ctx.globalAlpha = 1 - sweep;
        ANCIENT[man.kind](ctx);
      }
      if (sweep > 0.005) {
        ctx.globalAlpha = sweep;
        MODERN[man.kind](ctx);
      }
      ctx.restore();
    }
  }
}

/* The reform: a band of light crosses the board while the sets change, and the
   queen's own square keeps a little of it. */
function drawSweep(ctx: CanvasRenderingContext2D, cam: Camera, w: number, h: number, p: number) {
  const window = seg(p, 0.4, 0.47) * (1 - seg(p, 0.55, 0.64));
  if (window > 0.01) {
    const t = clamp01((p - 0.4) / 0.22);
    const x = lerp(-0.25, 1.25, t) * w;
    const g = ctx.createLinearGradient(x - w * 0.3, 0, x + w * 0.3, 0);
    g.addColorStop(0, "rgba(255,250,235,0)");
    g.addColorStop(0.5, `rgba(255,251,238,${0.58 * window})`);
    g.addColorStop(1, "rgba(255,250,235,0)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  }

  const queen = seg(p, 0.46, 0.56) * (1 - seg(p, 0.66, 0.78));
  if (queen > 0.01) {
    for (const rank of [0, 7]) {
      const q = squareQuad(cam, 3, rank);
      quadPath(ctx, q);
      ctx.fillStyle = `rgba(255, 244, 214, ${0.5 * queen})`;
      ctx.fill();
    }
  }
}

/* The sensors: the lattice wakes rank by rank, from the far side toward you. */
function drawLattice(ctx: CanvasRenderingContext2D, cam: Camera, lattice: number, time: number) {
  if (lattice < 0.01) return;
  ctx.save();
  ctx.lineCap = "round";
  const shimmer = 0.85 + 0.15 * Math.sin(time * 0.9);

  for (let i = 0; i <= 8; i++) {
    const t = clamp01((lattice - (i / 8) * 0.5) * 2.6);
    if (t < 0.01) continue;
    ctx.globalAlpha = t * 0.55 * shimmer;
    ctx.strokeStyle = SIGNAL;
    ctx.lineWidth = Math.max(0.8, cam.boardW * 0.0013);
    ctx.shadowColor = rgba(SIGNAL, 0.8);
    ctx.shadowBlur = 8;

    const a = project(cam, i / 8, 0);
    const b = project(cam, i / 8, 1);
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();

    const c = project(cam, 0, i / 8);
    const d = project(cam, 1, i / 8);
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.lineTo(d.x, d.y);
    ctx.stroke();
  }

  // nodes where the lattice crosses
  ctx.shadowBlur = 0;
  for (let r = 0; r <= 8; r++) {
    for (let f = 0; f <= 8; f++) {
      const t = clamp01((lattice - (r / 8) * 0.5) * 2.6);
      if (t < 0.02) continue;
      const at = project(cam, f / 8, r / 8);
      const s = Math.max(0.7, cam.boardW * 0.0016) * depthScale(cam, r / 8) * 1.6;
      ctx.globalAlpha = t * 0.7 * shimmer;
      ctx.fillStyle = SIGNAL;
      ctx.beginPath();
      ctx.arc(at.x, at.y, s, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.restore();
}

/* Brackets lock onto every square that holds a piece. */
function drawBrackets(ctx: CanvasRenderingContext2D, cam: Camera, lattice: number) {
  if (lattice < 0.12) return;
  ctx.save();
  ctx.strokeStyle = SIGNAL;
  ctx.lineCap = "square";

  ARMY.forEach((man, i) => {
    const t = clamp01((lattice - 0.18 - (i / ARMY.length) * 0.5) * 5);
    if (t < 0.02) return;
    const q = squareQuad(cam, man.file, man.rank);
    const cx = (q[0].x + q[2].x) / 2;
    const cy = (q[0].y + q[2].y) / 2;
    const w = Math.abs(q[1].x - q[0].x) * 0.46;
    const hh = Math.abs(q[2].y - q[0].y) * 0.46;
    const arm = Math.min(w, hh) * 0.55;
    const k = lerp(1.35, 1, t);

    ctx.globalAlpha = t * 0.85;
    ctx.lineWidth = Math.max(0.9, cam.boardW * 0.0018);
    const x0 = cx - w * k;
    const x1 = cx + w * k;
    const y0 = cy - hh * k;
    const y1 = cy + hh * k;

    ctx.beginPath();
    ctx.moveTo(x0, y0 + arm);
    ctx.lineTo(x0, y0);
    ctx.lineTo(x0 + arm, y0);
    ctx.moveTo(x1 - arm, y0);
    ctx.lineTo(x1, y0);
    ctx.lineTo(x1, y0 + arm);
    ctx.moveTo(x1, y1 - arm);
    ctx.lineTo(x1, y1);
    ctx.lineTo(x1 - arm, y1);
    ctx.moveTo(x0 + arm, y1);
    ctx.lineTo(x0, y1);
    ctx.lineTo(x0, y1 - arm);
    ctx.stroke();
  });
  ctx.restore();
}

function drawCoords(ctx: CanvasRenderingContext2D, cam: Camera, lattice: number) {
  const a = clamp01((lattice - 0.45) * 2.4);
  if (a < 0.02) return;
  const size = Math.max(9, cam.boardW * 0.0125);
  ctx.save();
  ctx.globalAlpha = a * 0.75;
  ctx.fillStyle = SIGNAL;
  ctx.font = `${size}px ui-monospace, "JetBrains Mono", monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  for (let f = 0; f < 8; f++) {
    const at = project(cam, (f + 0.5) / 8, 1);
    ctx.fillText("abcdefgh"[f], at.x, at.y + size * 1.5);
  }
  ctx.textAlign = "right";
  for (let r = 0; r < 8; r++) {
    const at = project(cam, 0, (r + 0.5) / 8);
    ctx.fillText(String(8 - r), at.x - size * 0.9, at.y);
  }
  ctx.restore();
}

/* Dust drifting over the sand becomes data drifting over the lattice. */
function drawMotes(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  w: number,
  h: number,
  p: number,
  time: number,
) {
  const modern = seg(p, 0.55, 0.85);
  const top = cam.horizon + cam.amp * depthScale(cam, 0) - cam.boardH * 0.8;
  const span = h - top;
  ctx.save();
  for (const m of MOTES) {
    const y = ((m.y - time * m.speed * 0.02) % 1 + 1) % 1;
    const x = (m.x + Math.sin(time * 0.25 + m.phase) * m.sway) % 1;
    const px = x * w;
    const py = top + y * span;
    const fade = Math.sin(y * Math.PI) * 0.75;
    ctx.globalAlpha = fade * lerp(0.32, 0.5, modern);
    ctx.fillStyle = modern > 0.5 ? SIGNAL : SAND_LINE;
    ctx.beginPath();
    if (modern > 0.5) {
      const s = m.size * 0.9;
      ctx.rect(px, py, s, s);
    } else {
      ctx.arc(px, py, m.size * 0.8, 0, Math.PI * 2);
    }
    ctx.fill();
  }
  ctx.restore();
}

/* The resting frame: a quiet horizon line under the board. */
function drawRest(ctx: CanvasRenderingContext2D, cam: Camera, rest: number) {
  if (rest < 0.02) return;
  const near = project(cam, 0.5, 1).y;
  ctx.save();
  ctx.globalAlpha = rest * 0.5;
  ctx.strokeStyle = rgba(SIGNAL, 0.5);
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(cam.cx - cam.boardW * 0.5 * rest, near + cam.boardH * 0.24);
  ctx.lineTo(cam.cx + cam.boardW * 0.5 * rest, near + cam.boardH * 0.24);
  ctx.stroke();
  ctx.restore();
}

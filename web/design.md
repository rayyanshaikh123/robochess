# RoboChess — The Design Package

The single creative document for the landing page. Written before the build,
consumed by the build. Every line of copy here ships verbatim.

Built against the 10K Websites skill in `SKILL.md` and its `references/`, with
two stated deviations. The hero journey is **drawn in code on a canvas** rather
than generated as an mp4, because the Higgsfield workspace has no credits yet
(see section 10). And `web/` is a Next.js app rather than the skill's
single-folder HTML target, so the build lives in React components instead of one
`index.html`. Everything else from the standard holds: band pacing and the flick
math, the entrance-per-beat choreography, the legibility system, the five
static-hero gates kept live, complete-without-the-hero, reduced motion in both
directions, the quality floor, and the copy gate.

What the canvas buys over footage: the journey reverses perfectly on scroll up,
weighs a few KB instead of a dozen MB, has zero anatomy to break, and the text
lane is guaranteed clear because we compose every frame ourselves.

## 1. The brand premise

**Chaturanga means four limbs.** The game began as an army drawn on the ground,
and every century since has moved it onto a new surface: sand, then boxwood,
then a screen. RoboChess moves it back. The board is real wood you touch, and
the machine comes to the board instead of the board going to the machine. One
idea, taught by every section: **the game stays on the table, and now the table
can see.**

## 2. The palette as CSS tokens

One direction, pulled from the subject's own world: a tournament hall at
midday. Parchment, ink, boxwood, walnut, deep forest green, and one rare signal
teal that appears only where the machine speaks.

```css
:root{
  --canvas:#F7F4EC;        /* warm parchment page ground, never pure white */
  --canvas-deep:#EFE8D9;   /* the hero's sand ground */
  --panel:#FDFBF6;         /* cards and raised surfaces */
  --ink:#16211C;           /* primary text, a green-black */
  --ink-soft:#5B6661;      /* secondary text */
  --forest:#1B4332;        /* primary, carried over from the Flutter app */
  --forest-deep:#123027;
  --signal:#0E9F8E;        /* the accent: sensors, live state, focus */
  --signal-ink:#0A6257;    /* the accent at text contrast */
  --wood-light:#E9D5B0;    /* boxwood */
  --wood-dark:#A9784F;     /* walnut */
  --sand:#D9C7A3;
  --sand-line:#B49A70;
  --rule:#E2DCCC;          /* hairlines */
}
```

The accent shows up in four places only: the sensor lattice in the hero, the
live dots, focus rings, and the one interactive moment. Nowhere else.

## 3. The type trio

- **Display: Fraunces.** A carved, high-character face that reads historic at
  heavy weights and modern when set tight. Used for every headline.
- **Body: Inter.** Quiet, neutral, used for paragraphs and interface text.
- **Mono: JetBrains Mono.** Coordinates, FEN strings, telemetry labels, kickers.

Variable files, so only one payload per family. Inter is never used as display.

## 4. The band map

Hero height 720vh, scroll range 620vh. Ramp per band
`f = min(0.025, (b - a) / 3)`, so every beat holds a plateau of about 110vh of
scroll with roughly 15vh eased edges, and 18vh of clear board between beats.

| Band | Range | What the board is doing | Copy (verbatim) | Entrance |
|---|---|---|---|---|
| 1 | 0.00 to 0.17 | Sand ground, grid scratched in by hand, four limbs standing, dust drifting | kicker `6th century, India` / **It started as an army.** / "Chaturanga: four limbs, sixty four squares, a grid drawn on the ground." | Scatter, grains gathering into letters |
| 2 | 0.20 to 0.38 | The checker pattern inks in square by square on a diagonal sweep, sand warms into boxwood and walnut | kicker `Persia, then everywhere` / **The grid learned to travel.** / "Shatranj carried the game west. The pieces took a new name in every language they passed through." | Grid snap, characters sliding into reading order |
| 3 | 0.41 to 0.59 | A sweep of light crosses the board, the old silhouettes become the modern set under it, the queen's square glows | kicker `Europe, around 1475` / **Then the queen was set free.** / "One rule change turned the slowest piece into the strongest, and the modern game was born." | Word punch with overshoot, the reform landing |
| 4 | 0.62 to 0.80 | A sensor lattice ignites under the squares rank by rank, brackets lock onto every occupied square, coordinates light up | kicker `Today` / **Now the board can see.** / "A camera reads the real pieces. The move appears in the app on its own." | Weave, characters arriving from above and below like threads |
| 5 | 0.83 to 1.00 | Everything resolves and rests, the board settles with a soft glow and live telemetry at the corners | h1 **Chess you can touch, on a board that watches.** / "RoboChess joins a real chessboard, a camera and a chess engine, so the game never has to move to a screen." / CTA `Open the board` and `See how it works` | Word by word rise into a staged settle, headline then subline then buttons |

Flick math, checked against the ranges above at an 800px viewport: a band runs
about 893px of scroll, so a normal 120px flick gives roughly 7 steps per beat
and an aggressive 360px double flick still lands about 2 steps inside the
fully-settled plateau. No beat is skippable and no beat is too short to read.

## 5. The static-hero copy block

Phones, portrait tablets, landscape phones, coarse-pointer portrait, and
reduced motion all get band 5 composed as a still, over the board rendered once
at its resting frame. Same words, no journey behind them:

**Chess you can touch, on a board that watches.**
"RoboChess joins a real chessboard, a camera and a chess engine, so the game
never has to move to a screen."
`Open the board` and `See how it works`

## 6. The below-fold outline

Every section funnels to one call to action: **get RoboChess running**, which
has two routes, the browser build at `/app/` and the Android APK at
`/downloads/robochess.apk`. There is no form. The product is the app, so the
page sends people to it instead of collecting an address.

The APK is a real release build of the Flutter app (`flutter build apk
--release`, version 1.0.0, about 54 MB). It is served straight from
`web/public/downloads/`. That is a large file to keep in git, so the honest
alternative is a GitHub Release asset with the button pointing at its URL.

1. **The four limbs.** The culture section and the site's central device.
   Chaturanga named its army in four parts, and the system is built in four
   parts that line up with them: Padati the infantry is the sixty four watched
   squares, Ashva the cavalry is the engine, Gaja the elephant is the eye, Ratha
   the chariot is the link. Each card names the ancient limb, the piece it
   became, and the part of RoboChess it maps to.
2. **The long game.** A drawn timeline, six stops from the ashtapada grid to the
   board that reports its own position. This is where the history is told plainly.
3. **How the board sees.** The technical pipeline as a drawn diagram: the camera
   looks, the model finds the squares, the position becomes FEN, the engine
   answers, the app and the board stay in step.
4. **What you can do with it.** The real feature set: play the engine, play a
   friend, solve puzzles, analyse a game, speak a move, pair a board over
   Bluetooth, and keep playing when the internet drops.
5. **Inside the app.** The screenshot carousel, and the second scroll-driven
   moment on the page. One drawn phone body is pinned at the centre of the
   stage while the six screens ride an arc behind it: scrolling turns the arc,
   each screen swings in, lands inside the phone, and swings out the far side.
   The arc is a closed ring, so both sides of the phone always carry screens and
   the seam sits out past the fade where it cannot be seen. Everything off
   centre is blurred from 1.6px up to 10px, scaled back and dipped along the
   curve, so there is only ever one thing to read. The caption under the phone
   swaps with whichever screen is centred.

   The scroll itself is finite even though the ring is not: progress across the
   pinned track maps to screens one through six and stops, and the page moves on.
   The Android download rides inside the stage and eases in as the last screen
   lands, so it reads as the payoff of the carousel rather than something that
   turns up afterwards. Its space is reserved the whole time, so nothing shifts
   when it arrives.

   Tabs are Home, Play, Friends, Analysis, Learn and Connect, taken from the
   Flutter app's own navigation bar. Screenshots live in `web/public/screens/`
   as `home.png`, `play.png`, `friends.png`, `analysis.png`, `learn.png` and
   `connect.png`. A tab with no file yet keeps its frame and says so, rather
   than showing a broken image.

   The same five gate strings as the hero send phones, portrait tablets,
   landscape phones and reduced motion to a plain carousel instead: the phone,
   the caption, arrow buttons and dots, no arc and no pinned track.

   One trap worth recording: `overflow: hidden` on the section around a sticky
   stage makes that section the sticky element's scroll container and the stage
   silently stops sticking. The clip belongs on the sticky element itself.
6. **Straight answers.** The FAQ, written against the real objections: do I need
   the hardware, does it work offline, is my camera good enough, is it finished,
   can I read the code, where do my games live.
7. **Open the board.** The closing call to action and the footer.

No invented metrics anywhere. No fake store badges, no testimonials, and the
page says plainly that the project is still being built.

## 7. The vector layer plan

Everything is drawn by hand: no icon font, no image sprites.

- **The app's own logo** carries the page's whole argument already: a war
  elephant on parchment on one side, a modern knight in the dark on the other,
  a king split down the middle and an arrow crossing between them. It sits in
  the header and the footer. The drawn 8x8 mark stays as the favicon.
- **The signature element, the Board of Ages.** One canvas-drawn 8x8 board in
  true perspective, aged by scroll progress across five eras. Its lattice motif
  reappears as the section rule, as the wake-the-board panel, and as the footer
  mark. Remove it and the page is a different page.
- **An inline SVG icon set** drawn for this site, stroked in the same weight as
  the lattice.
- **Self-drawing lines** on the timeline and the pipeline diagram, drawn on
  entrance with `stroke-dasharray`.
- **Whisper-level life,** one per section: dust motes that become data motes in
  the hero, a slow shimmer on the section rules, the live dot's pulse.
- **The interactive moment** is the arc carousel in the app section, which the
  visitor drives with scroll. A separate press-and-hold demo lived here in an
  earlier pass and was cut: it restated what the pipeline section already says,
  and the page reads better without it.
- **The environment layer:** one fixed ground behind everything, a faint 8x8
  sand grid with two slow radial washes on a 90 second drift, so scrolling feels
  like moving through a hall rather than past stacked sections.

## 8. The engineering list

The hero runs the full standard from `references/scrub-pipeline.md`, minus the
parts that only exist for video files. What ships:

- Progress through a pinned 720vh hero mapped to 0..1.
- A dt-normalized lerp toward the target so the feel is identical at 60Hz and
  144Hz, in a rAF loop that rests when converged and when the hero is off screen.
- Delta-gated DOM writes for every band opacity, every `--k`, and every readout.
- The canvas repaints only on change, capped at 30fps for ambient-only frames,
  and stops on a hidden tab.
- Band pacing in scroll distance with smoothstep ramps, validated by the flick
  math above.
- The legibility system: a global parchment veil over the stage, a per-band
  scrim that deepens with `--k`, an ink text shadow token, and chips for the
  small telemetry lines.
- The five static-hero gates, identical strings in CSS and JS, re-evaluated live
  on rotation, resize and preference changes.
- Complete without the hero: if the canvas fails, the composed still block and
  the whole page below still work.
- Reduced motion honored completely and live in both directions.
- The quality floor: semantic landmarks, a skip link, focus-visible in the
  accent, 44px touch targets under coarse pointers, real title and meta, an
  inline SVG favicon, and no font payload that is not in use.

## 9. The copy gate

Every viewer-facing line above ships verbatim. Before anyone sees the page it
must grep clean: zero em dashes, zero instances of leverage, seamless, empower,
unlock, robust, actionable, data-driven and solutions, and zero of the quieter
tells (testament, landscape, delve, elevate, vague attributions, generic big
finishes). The designed devices in this package, like the four-limbs mapping
and the triplet in the pipeline section, are craft and stay.


## 10. The hero footage question

The hero is drawn in code today. The Higgsfield CLI is installed and
authenticated (`higgsfield auth status` reports the account), but the workspace
is on the free plan with **0 credits**, so nothing can be generated yet. At the
proven defaults a starting frame costs about 2 credits and a 6 second
image-to-video shot costs roughly 10 to 55 credits depending on the model, so
one hero pipeline plus a retry needs credits on the account first.

When credits exist, the shot is already storyboarded by the band map in section
4: one continuous push across a real board while the light changes era, ending
on the composed resting frame the settle band sits over. The build swaps the
canvas for the video behind the same progress drive, and everything else in
section 8 stays exactly as it is.

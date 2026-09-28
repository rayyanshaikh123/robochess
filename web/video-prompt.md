# The hero video prompt

Generate this wherever you like. Bring back an mp4 and I will wire it in.

It is written to the twelve hero-video laws in `references/prompt-laws.md`, so
it obeys the ones that decide whether footage works on a scroll site: the motion
reads as "down" while you scroll down, it is one subject on one unbroken path
with no cuts, the ending is composed as a resting frame rather than a random
last moment, and the top third of every frame stays calm so the captions can
live there.

---

## 1. The starting frame (image, 16:9, highest resolution offered)

```
A low three-quarter view across an ancient ashtapada board, an eight by eight
grid scratched into fine pale sand on a worn stone table, composed as the first
moment of a slow forward glide along the board's surface. Carved sandstone
chaturanga pieces stand in their opening rank: squat foot soldiers, blunt
horses, rounded elephants with short tusks, small chariots with a single wheel.
Warm low sunlight rakes in from the left, long soft shadows, fine dust hanging
in the light. The palette is sand, ochre, worn stone, deep green shadow. The
scene fills the frame edge to edge and continues past it; the upper third of
the frame is quiet receding depth, soft shadow and haze above the far edge of
the board, with no objects and no bright highlights in it. Cinematic,
photorealistic, shallow depth of field, 16:9.
No text, no logos, no lettering anywhere.
```

Why it is written this way: the calm upper third is where the captions land, and
it is described as part of one continuous world rather than as empty space,
because asking a generator for "empty darkness at the top" gets you a literal
black panel and costs a re-roll.

---

## 2. The motion (image to video, 1080p, 6 seconds, no audio)

Feed the approved image above as the start frame.

```
One continuous shot, no cuts. The camera glides slowly forward and slightly
downward along the surface of the board, from the near edge toward the far
edge, in a single unbroken move at one steady speed. As it travels, a soft
sweep of warm light crosses the board from left to right, and everything the
light has passed has changed: the sand grid has become a polished tournament
chessboard in boxwood and walnut, and the carved sandstone pieces have become
modern weighted chess pieces in cream and dark walnut, standing in the same
squares they already occupied. Nothing jumps position; only the material
changes, and only behind the sweep. After the light passes, fine lines of pale
teal light ignite along the edges of the squares, rank by rank, running away
from the camera, and small bracket marks settle onto the squares that hold a
piece. The scene stays alive throughout: dust drifting in the light, faint
grain moving in the wood, the teal lines breathing very slightly. The shot ends
at rest: the whole board sits still and complete in the lower two thirds of the
frame with generous space above and below it, the teal lattice glowing softly
under the pieces, the camera stopped, the light settled. The upper third of the
frame stays quiet the whole way through.
No text or lettering anywhere.
```

---

## 3. If your provider is text to video only

Paste both blocks as one prompt, with the image block first and the motion block
second, and add `16:9, 6 seconds, 1080p` at the end.

---

## 4. What to send back, and where to put it

- **Format:** mp4, H.264, **1080p**, **6 seconds**, 16:9, no audio. Do not
  generate at 4K; it gets re-encoded and compressed for the web anyway and only
  multiplies the cost.
- **Save it to:** `web/public/media/hero-scrub.mp4`

Then tell me and I will do the rest:

1. Inspect the start, middle and end frames for anatomy, stray logos and whether
   the ending really rests.
2. Re-encode it for scrubbing with a short keyframe interval (`-g 8`), which is
   the difference between smooth and choppy when scroll drives `currentTime`.
3. Pull a poster frame and the composed ending frame.
4. Wire it behind the same scroll drive the board already uses, so the five
   caption beats, the band pacing, the legibility system, the five static-hero
   gates and reduced motion all keep working untouched.

## 5. What makes a take usable

Check these before you send it over, because they are what a re-roll usually
fixes:

- The camera never reverses or cuts. One heading, one speed.
- The pieces never jump squares or change count during the sweep.
- The last frame is a composed resting frame, not a mid-move blur. The site
  comes to rest exactly there, and the header sits over the top of it.
- The top third has nothing in it that the headline would fight.
- No lettering anywhere, including on the board edge.

If a take fails three times, the concept is the problem, not the prompt. The
fallback that always works: drop the era change and shoot only the modern board
with the teal lattice igniting, and let the page tell the history in the
sections below.

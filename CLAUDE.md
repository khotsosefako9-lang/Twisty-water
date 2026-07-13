# Twisty Water — Launch Asset Studio

Interactive showcase for the Twisty Water launch visual library (canned still water, 4 flavours, organic-only launch, Gqeberha seeding hub).

## Run it
No build step. Open `index.html` directly, or serve locally for best video behaviour:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

## Structure
```
index.html                 # entire app: single file, zero dependencies (Google Fonts only)
assets/
  img/<flavour>/           # full-res stills: pour / serve / flatlay-torn / poster-hydrated / infographic
  img/range/               # multi-flavour assets (lineup, group posters)
  video/                   # h264 mp4 (cooler-summer-02 was transcoded from HEVC .mov)
  thumbs/                  # 640px grid thumbnails (lightbox loads the full PNG)
  posters/                 # video poster frames
REGENERATE-QUEUE.md        # every warped asset + a fix prompt for Nano Banana 2
```

## How the app works
- **Single source of truth:** the `ASSETS` array at the top of the `<script>` in `index.html`. Every card renders from it. To add an asset: drop the file into `assets/`, generate a thumb, add one object to the array.
- **Flavour worlds:** `html[data-flavour]` drives CSS variables (`--wash`, `--accent`…). Switching a flavour recolours the entire page and crossfades the hero pour video. Add a flavour = one CSS block + one chip + one hero `<video>`.
- **Status grading:** `ready` (post as-is) / `review` (fine at feed size, micro-copy soft) / `regen` (label warped — see queue). The ⚠ toggle filters to the regen queue.
- Lightbox supports keyboard (←/→/Esc), videos play with controls, `prefers-reduced-motion` respected.

## Regenerate a thumbnail
```bash
ffmpeg -i assets/img/lemon/pour.png -vf "scale=640:-2" -q:v 5 assets/thumbs/lemon-pour.jpg
```

## Brand notes
- Brand voice: "Dynamic. Healthy. Refreshing." Full-bleed colour, maximum visual energy — never subtle.
- Colour worlds: Lemon yellow / Cucumber sage / Mint green / Rosemary lilac; brand-blue script logo is the constant.
- Cucumber assets are known-warped and stay off the main feed until regenerated (see REGENERATE-QUEUE.md).

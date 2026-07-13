# Regeneration Queue — Label Warp Fixes

The warped lettering is baked into the pixels of these renders, so it can't be patched in post — the fix is regeneration in **Nano Banana 2 / Kling 3.0 Turbo** using a clean label reference. The three cleanest label renders in the library are:

- `assets/posters/pour-lemon.jpg`
- `assets/posters/pour-mint.jpg`
- `assets/posters/pour-rosemary.jpg`

(The pour-still images these used to point to were removed when the duplicate pour-still row was cut from the feed — the pour-video poster frames are clean stand-ins for the same reference.)

Crop the can from one of these and attach it as the **identity/reference image** on every regeneration below. That single change fixes most warping, because the model copies the reference typography instead of hallucinating it.

## Universal prompt suffix (append to every regen)

> The can label must exactly match the reference image: script wordmark reading "Twisty Water" in brand blue, blue wave swirl logo, tagline "DYNAMIC. HEALTHY. REFRESHING." in small caps. Render all label text sharp, correctly spelled, and undistorted. No invented words or extra characters.

## Queue (highest impact first)

| # | Asset | Problem | Regen brief |
|---|-------|---------|-------------|
| 1 | `video/lineup-float.mp4` + `assets/unused/img/range/lineup-float.png` *(no longer in the feed — kept only as the hero's "full range" background video)* | Logo renders "Twistylvlaten" on all four cans | Four 500ml silver cans (lemon, cucumber, mint, rosemary & lemon) floating on sky-blue, fruit and herbs suspended around them, soft studio light. Regenerate still first, then image-to-video in Kling. |
| 2 | `assets/unused/img/range/poster-poolside.png` *(dropped from the feed — the panorama crops took over the pinned row)* | Cans read "Healthy Living" instead of the brand | Four cans on travertine poolside ledge, palm shadow, headline "TWISTY WATER" (add typeset headline in Canva after — generate the scene with blank-ish cans matching reference). |
| 3 | `assets/unused/img/range/poster-healthy-living.png` *(dropped from the feed — see #2)* | "Twisty Waters" + garbled flavour descriptors | Three cans on round wooden table, lush plant backdrop, morning light. Re-typeset the overlay copy in Canva rather than asking the model to render it. |
| 4 | `video/pour-cucumber.mp4` *(held out of the pour-video row; still used by the hero's cucumber background)* | Known cucumber warp ("Trinity Water" read) | Match the other three pours exactly: hand pours 330ml can into ice glass, seafoam-green world, cucumber slices on surface. Reference: `assets/posters/pour-mint.jpg` composition. |
| 5 | `img/cucumber/serve.png` | "CUCJUB8 R & MINT" sub-line | Can + can-glass with cucumber ribbons, marble surface, grey wall. |
| 6 | `img/cucumber/flatlay-torn.png` | "Ccoarabeer" | Torn-paper reveal over fresh cucumber slices, sage paper. |
| 7 | `img/lemon/flatlay-torn.png` | "ORGAING… REREBSHING" | Torn yellow paper over lemon slices. |
| 8 | `img/rosemary/flatlay-torn.png` | "Ressmmary" | Torn lilac paper over rosemary sprigs + lemon. |
| 9 | `assets/unused/img/mint/flatlay-torn.png` *(dropped from the feed — the torn-paper row is lemon/cucumber/rosemary only)* | Logo tail warp | Torn sage paper over wet mint leaves. |
| 10 | `img/lemon/infographic.png` | Garbled tagline behind callouts | Generate the product scene only; add callout arrows/copy in Canva. |
| 11 | `img/cucumber/infographic.png` | "CUCUINBIER" | Same approach — scene from model, copy typeset in Canva. |
| 12 | `img/rosemary/poster-hydrated.png` | New asset still carries "Infussd" typo + garbled tagline on the can (headline type is clean) | Same split as the others — re-typeset can micro-copy isn't worth it via prompt; regenerate the can render with the reference lock, keep the purple splash layout as-is. |
| 13 | `img/rosemary/infographic.png` | New asset's can tagline reads "HEALFHY:HHY.REFRESHING.." | Callout copy and headline are clean (Canva-typeset already); regenerate just the can render with the reference lock. |

## Rule of thumb going forward

Anything the model renders **as typography** will eventually warp. The reliable split:
- **Model renders:** the can (with reference lock), the scene, the light.
- **Canva renders:** headlines, callouts, flavour descriptors, CTAs.

The Stay Hydrated posters mostly follow this split already — which is why their layout type is clean and only the on-can micro-copy is soft.

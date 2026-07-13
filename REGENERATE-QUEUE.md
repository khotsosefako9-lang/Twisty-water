# Regeneration Queue — Label Warp Fixes

The warped lettering is baked into the pixels of these renders, so it can't be patched in post — the fix is regeneration in **Nano Banana 2 / Kling 3.0 Turbo** using a clean label reference. The three cleanest label renders in the library are:

- `assets/img/lemon/pour.png`
- `assets/img/mint/pour.png`
- `assets/img/rosemary/pour.png`

Crop the can from one of these and attach it as the **identity/reference image** on every regeneration below. That single change fixes most warping, because the model copies the reference typography instead of hallucinating it.

## Universal prompt suffix (append to every regen)

> The can label must exactly match the reference image: script wordmark reading "Twisty Water" in brand blue, blue wave swirl logo, tagline "DYNAMIC. HEALTHY. REFRESHING." in small caps. Render all label text sharp, correctly spelled, and undistorted. No invented words or extra characters.

## Queue (highest impact first)

| # | Asset | Problem | Regen brief |
|---|-------|---------|-------------|
| 1 | `video/lineup-float.mp4` + `img/range/lineup-float.png` | Logo renders "Twistylvlaten" on all four cans | Four 500ml silver cans (lemon, cucumber, mint, rosemary & lemon) floating on sky-blue, fruit and herbs suspended around them, soft studio light. Regenerate still first, then image-to-video in Kling. |
| 2 | `img/range/poster-poolside.png` | Cans read "Healthy Living" instead of the brand | Four cans on travertine poolside ledge, palm shadow, headline "TWISTY WATER" (add typeset headline in Canva after — generate the scene with blank-ish cans matching reference). |
| 3 | `img/range/poster-healthy-living.png` | "Twisty Waters" + garbled flavour descriptors | Three cans on round wooden table, lush plant backdrop, morning light. Re-typeset the overlay copy in Canva rather than asking the model to render it. |
| 4 | `img/cucumber/pour.png` + `video/pour-cucumber.mp4` | Known cucumber warp ("Trinity Water" read) | Match the other three pours exactly: hand pours 330ml can into ice glass, seafoam-green world, cucumber slices on surface. Reference: `mint/pour.png` composition. |
| 5 | `img/cucumber/serve.png` | "CUCJUB8 R & MINT" sub-line | Can + can-glass with cucumber ribbons, marble surface, grey wall. |
| 6 | `img/cucumber/flatlay-torn.png` | "Ccoarabeer" | Torn-paper reveal over fresh cucumber slices, sage paper. |
| 7 | `img/lemon/flatlay-torn.png` | "ORGAING… REREBSHING" | Torn yellow paper over lemon slices. |
| 8 | `img/rosemary/flatlay-torn.png` | "Ressmmary" | Torn lilac paper over rosemary sprigs + lemon. |
| 9 | `img/mint/flatlay-torn.png` | Logo tail warp | Torn sage paper over wet mint leaves. |
| 10 | `img/lemon/infographic.png` | Garbled tagline behind callouts | Generate the product scene only; add callout arrows/copy in Canva. |
| 11 | `img/cucumber/infographic.png` | "CUCUINBIER" | Same approach — scene from model, copy typeset in Canva. |

## Rule of thumb going forward

Anything the model renders **as typography** will eventually warp. The reliable split:
- **Model renders:** the can (with reference lock), the scene, the light.
- **Canva renders:** headlines, callouts, flavour descriptors, CTAs.

The Stay Hydrated posters mostly follow this split already — which is why their layout type is clean and only the on-can micro-copy is soft.

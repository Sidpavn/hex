# Hex – UI rules

The UI must not look AI-generated. Before adding or changing any UI, check it against this list.

## Banned (the usual AI tells)
- Emoji used as icons or decoration. Use one icon set (or custom painted glyphs) consistently.
- Glow: coloured `BoxShadow` / `Shadow` with a blur and no offset, neon halos, shimmer on text.
- Gradient text (`ShaderMask` on titles) and gradient buttons. Use flat fills.
- Wide-tracked ALL-CAPS micro labels (`letterSpacing` > 1) as the default label style. Sentence case, normal tracking.
- Glassy translucent panels with a 1px gold/white hairline border as the standard container.
- Ambient decoration with no function: floating particles, fireflies, drifting shapes.
- Bounce/elastic curves (`elasticOut`, `easeOutBack`) on routine UI. Use `easeOutCubic` / short fades, 150–250ms. Motion only where it communicates state change.
- One radius for everything (e.g. 18). Vary radius by element role (small controls < cards < sheets).
- Symmetric, centred, evenly-spaced "stack of cards" screens. Use real hierarchy: one dominant element, the rest quieter.
- Generic copy: "Embark", "Unleash", "Your journey", motivational filler. Write plain, specific labels.

## Required
- A defined type scale (3–4 sizes, 2 weights) in the `ThemeData` text theme. No ad-hoc `fontSize: 12.5`.
- Colour comes from `Pal`/theme only; at most one accent. Neutral surfaces carry most of the screen; accent is for the primary action and state.
- A spacing scale (4/8/12/16/24); no one-off values.
- Elevation expressed by surface tone or a real offset shadow, not glow.
- Every screen has one clear primary action; secondary actions are visibly lower weight.
- Prefer removing a decoration over adding one. If an element has no function, cut it.

## Keep screens light (diner screens)
- One screen, one job. At most about five facts visible at once; a card has at most three lines. Anything more goes behind a tap, onto its own page.
- Help appears right next to what was tapped (an inline line under it), never in a fixed spot at the top of a page that scrolls.
- Text is never clipped. A box either grows to fit its text or the text is made shorter. No fixed-height text boxes.
- News during play is a toast: small, top-left, self-dismissing. It is not a permanent line on a panel.
- Buttons and rows say what they do and what you get ("Extend dining room: +2 rows"), never a bare "Max", "Deeper" or "Owned".
- Lists of people or things are compact rows. Details and actions open on their own page.

## Self-check before finishing a UI change
1. Could this screen be swapped for any other app's "dark fantasy game" template? If yes, make a choice that is specific to Hex (the hex grid, its pieces, its rules).
2. Count distinct effects (glow, gradient, blur, bounce). More than one per screen is too many.
3. Would a designer have drawn this, or does it just look "polished by default"? Cut until it looks decided.

## Pixel UI kit (how the rules above are met)
- Sprites, icons and units come from `assets/pixel/sprites.txt`; add art there, never emoji. Icons in strings are `:name:` tokens rendered by `PxText`.
- Use `PixelBox` / `Panel` / `GoldButton` / `Choice` / `PxBar` / `HexBadge` from `lib/ui/widgets.dart`. They draw on a whole-device-pixel grid (`PixelUi.unit`).
- Font is VT323. `PixelTextScaler` (set in `main.dart`) snaps every font size to a crisp multiple, so just write normal sizes; don't add `letterSpacing`.
- No glow, gradients, blur, rotation, fractional scaling or fades. Motion steps in whole pixels. Page transitions are cuts.
- Diner art is isometric and generated: edit `tools/gen_diner_art.py` (toolkit in `tools/iso.py`), run it, restart the app. Output goes to `assets/diner/`; don't hand-edit the PNGs.
- Previews: `PIXEL_PREVIEW=<png> flutter test test/pixel_preview_test.dart` (board) and `UI_PREVIEW=<dir> flutter test test/ui_preview_test.dart` (screens), `DINER_PREVIEW=<png>` / `DINER_SCREEN=<png>` with `test/diner_preview_test.dart` (diner board / build screen).

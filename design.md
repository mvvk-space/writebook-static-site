# Design — Writebook (static site generator fork)

Locked design system. Every Hallmark run in this project reads this file first
and defers to it. Pages share the system; they vary only in macrostructure and
archetype. Amend this file — never override it per page.

## System

- Genre · **editorial**
- Macrostructure family
  - Library index (`books#index`) · **Index-First** — the grid of plates *is* the page
  - Book table of contents (`books#show`) · **Catalogue** — title page over a shelf of leaf plates
  - Leaf reading page (`leafableables#show`) · **Long Document** — one measure of type
- Theme · catalog **Newsprint** (light paper · roman-serif display · warm accent)
- Axes · light / roman-serif / warm (printer's red `oklch(46% 0.165 33)`)
- Nav · masthead on the library (double rule), running head on inner pages
- Footer · single-line colophon (`Made with Writebook` + prev/next), hairline above

## Tokens

`app/assets/stylesheets/colors.css` is the live source of truth (Propshaft loads
it after every other sheet). Root `tokens.css` mirrors it for portability.

```css
:root {
  --color-paper:      oklch(96.5% 0.012 82);
  --color-paper-2:    oklch(91.5% 0.014 82);
  --color-ink:        oklch(20% 0.012 65);
  --color-ink-2:      oklch(62% 0.014 75);
  --color-border:     oklch(62% 0.014 75);  /* control + plate outlines, ≥3:1 */
  --color-muted:      oklch(46% 0.013 70);
  --color-rule:       oklch(78% 0.013 80);
  --color-accent:     oklch(46% 0.165 33);
  --color-accent-ink: oklch(96.5% 0.012 82);
  --color-focus:      oklch(46% 0.165 33);
  --color-marker:     oklch(68% 0.15 65);   /* the ochre "last read" ribbon */
  --color-highlight:  oklch(90% 0.115 88);  /* search band */

  --font-display: "Newsreader", ui-serif, Georgia, serif;
  --font-body:    "Spectral", ui-serif, Georgia, serif;
  --font-mono:    "IBM Plex Mono", ui-monospace, Menlo, monospace;

  /* 4-pt spacing scale: --space-3xs … --space-4xl. See tokens.css.        */
  /* Type scale, 1.25 (major third): --text-xs … --text-display.           */

  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in:  cubic-bezier(0.7, 0, 0.84, 0);
  --dur-none: 0ms; --dur-micro: 100ms; --dur-short: 180ms; --dur-long: 300ms;

  --radius-plate: 2px; --radius-btn: 2px; --radius-input: 2px; --radius-card: 3px;
  --control-size: 2.75rem;  /* 44px — shared height for controls and fields */
}
```

## Typography

- Display · Newsreader (variable 400–700), roman only, weight **700** on headings
- Body · Spectral 400; semibold 600 for labels and strong; italic **only** in running prose
- Mono · IBM Plex Mono — code, word counts, tabular figures (the one outlier register)
- Display tracking · `-0.015em` to `-0.025em`
- Measure · `65ch` for prose; the library and book pages widen to `110ch`
- Scale · major third (1.25). Section leaves cap at `--text-display`
- Self-hosted (OFL) via `fonts.css` + `app/assets/fonts/` — no font-CDN request, so the static export stays self-contained

## Spacing

4-point named scale in `tokens.css`. Pages use `var(--space-*)` and the existing
`--block-space` / `--inline-space` roles; raw values are not introduced.

## Motion

- The Newsprint register is print: state changes land instantly (`--dur-none` /
  `--dur-micro`). Only functional movement animates — sidebar, dialog, lightbox.
- Reveal pattern · **none**. Nothing fades in on scroll; content is present.
- Removed · the infinite `pulse` loop, the `zoom-fade` flyaway, slide view-transitions.
- Kept · one-shot shake/wiggle on form errors, the save loader mask, a crossfade page turn.
- Reduced-motion fallback · all animation collapses to 0.01 ms (see `_reset.css`).

## Microinteractions stance

- Silent success · no celebratory toast; copy-to-clipboard is an opacity flash on the button.
- Focus rings appear instantly and never animate in.
- Hover is a crisper hairline, never a glow or a lift.
- `transition-all` is banned; every transition names its properties.

## CTA voice

- Primary · ink fill, `--radius-btn`, `0.45em 0.9em` padding, semibold serif label
- Secondary · transparent fill, 1px `--color-rule` outline, same radius and padding
- Icon-only controls are square plates at `--btn-size` (2.75em → ≥44px touch target)

## Per-page allowances

- Library index MAY run the grid wider than the reading measure (`110ch`).
- Book page MAY use the two-column plate + catalogue layout.
- Leaf pages MUST NOT use enrichment — the type carries the page.
- Editing/admin pages inherit the system unchanged; no separate treatment.

## What pages MUST share

- The wordmark (`--font-display`, weight 600) and the Writebook icon.
- The accent and its restraint — printer's red on links, focus, markers; never a fill.
- The display + body + mono trio.
- The CTA voice (radius, border, padding rhythm).
- The hairline rule as the only divider.

## What pages MAY differ on

- Macrostructure within the page family (Index-First / Catalogue / Long Document).
- The header's role: masthead (library) vs running head (inner pages).

## Exports

`app/assets/stylesheets/colors.css` and root `tokens.css` carry every token.
For Tailwind v4 `@theme`, DTCG `tokens.json`, or shadcn/ui variables, ask
*"extend design.md with Tailwind exports"*.

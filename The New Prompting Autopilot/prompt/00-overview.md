---
description: Product and technical spec for the Writebook page-turn reader
---

# Writebook Reader — the page-turn edition

Writebook should look like a book, not a blog. The public reading surface
becomes a 3D page-turn reader: a cover that opens, a spread of real paper, and
pages that bend, cast shadows, and land with weight. The editing app stays where
it is. This spec is about what a reader meets.

## The target

Think of the book and magazine readers circulating on Threads and X: the page
does not slide or crossfade. It **lifts**, **bends along the gutter**, drags a
shadow across the page underneath, and settles flat. The paper has thickness.
The typography stays crisp.

That last clause is the hard constraint. The page is a real DOM page with real
text at rest. Any 3D effect is a transform on that DOM, never a rasterized
screenshot of it. If a technique cannot keep text selectable, searchable, and
legible for a screen reader, it is not the default.

## What it is not

- Not a WebGL text renderer. No canvas text, no texture atlas of the page, no
  three.js in v1. See **Why not three.js first** below.
- Not an editor change. The existing edit UI, autosave, and Turbo streams stay.
- Not a new document format. The reader consumes the same leaves the app
  already renders.
- Not a separate mobile app. One responsive reader, one codebase.

## Experience

### Desktop

The book opens centered on a warm paper field. Two pages sit side by side,
joined by a soft gutter shadow. The left page carries the running head and the
verso folio; the right page carries the recto folio. The spread is scaled to
the viewport height, never cropped. A hairline progress rule sits below the
book, with the current page number in mono.

- **Cover**: closed at first visit. A cloth-textured board with the title set in
  Newsreader, a foil hairline, and the author name. Click, Enter, or a drag on
  the fore-edge opens it. The cover swings from the spine and settles onto the
  left side; the first spread is underneath.
- **Turn**: drag the outer third of a page toward the spine. The page follows
  the pointer 1:1, bends, and darkens near the fold. Release past 28% of the
  page width, or with enough velocity, and it completes; otherwise it snaps
  back. A click on the outer margin, `→`, `PageDown`, or `Space` turns forward;
  the mirrored inputs turn back.
- **Rest**: only the current spread and one spread either side are mounted.
  Everything else is unmounted, not merely hidden.

### Mobile

One page at a time, full-bleed with a safe-area gutter. A horizontal swipe turns;
a vertical drag still scrolls the page if its content overflows (code blocks,
tall images). The turn is the same engine with a single leaf. The spread
collapses below 720px of viewport width.

### Reading furniture

- Page numbers and running heads are generated, not authored.
- A thin scrubber shows position; hovering it shows a page thumbnail? No.
  Hover shows the page number only. Thumbnails are explicitly out of scope for
  v1.
- The table of contents opens as a paper insert on the left page (desktop) or a
  sheet from the bottom (mobile). It maps each leaf to its first page.
- Bookmarks are page-level and stored per user; anonymous readers get
  `localStorage`.
- Resume puts the reader on the last page read, by anchor, not by number.
- Search results jump to the page containing the hit and flash the existing
  highlight band (`--color-highlight`).
- A **Continuous** control switches to the current long-document route. That
  route remains the no-JS and screen-reader-canonical view.

### Where it lives

- `GET /:id/:slug/read` renders the reader for a published book.
- `GET /:book_id/:book_slug/:id/:slug/read` opens at a leaf's first page.
- Signed-in editors can open the reader for an unpublished book with a
  persistent **Draft** ribbon; the reader otherwise behaves identically.
- `?page=N` is the canonical page address. It is updated with
  `history.replaceState` during turns and pushed on deliberate navigation.
- The static export uses the same reader at the book root.

## Visual direction

The existing `design.md` is the authority for palette, type, and spacing. The
reader adds a physical layer on top of it, and `design.md` must be amended (not
overridden per page) with a **Reader** section covering:

- **Paper**: `--color-paper` stock, a 1px `--color-rule` edge, and a subtle
  fibre grain drawn with a repeating linear-gradient. No bitmap texture.
- **Ink**: unchanged. Body text stays Spectral at the existing reading size; do
  not shrink the type to fit the prop.
- **Accent**: the printer's red appears only on the bookmark ribbon, the
  progress tick, and the focus ring.
- **Cover**: cloth in `--color-paper-2`, title in `--color-ink`, foil rule in
  `--color-accent`. Theme variants follow the book's existing `theme`.
- **Light**: one warm key light from the upper left. A fixed 2% Y-rotation on
  the closed book gives it presence without making text swim. Shadows are
  gradients, not blurred boxes.
- **Page geometry**: 3:4 page, scaled by a single `--page-scale` custom
  property. Margins are outer 48, inner 56, head 56, foot 64 at scale 1.
  Prose measure is 46–54 characters on a page.
- **Motion**: 640ms turn with `cubic-bezier(.2,.7,.2,1)`; drag is 1:1; the
  landing has no bounce. `prefers-reduced-motion` replaces the turn with the
  crossfade the design already allows, at 120ms.
- **No** ambient animation, floating dust, page-edge particles, or idle
  breathing. The book is still until touched.

## Why not three.js first

Three.js earns its place when the page must deform as a continuous mesh with
specular lighting. It costs a 150KB+ runtime, a rasterized page texture that
blurs under zoom and breaks text selection, and a static export that must ship
the whole engine. It also makes the accessible page a second-class copy.

The default engine is CSS 3D on the real DOM. The API is written so a WebGL
curl can be added behind the same `FlipEngine` interface later, for the drag
phase only, without changing pagination, routing, or content. That is milestone
12, and it is optional.

## Architecture

Five modules, all in `app/javascript/reader/`, no build step, loaded through
importmap.

### 1. `reader.js` — shell and state

Owns book metadata, current spread, direction, and the URL. Renders the static
frame and hands pages to the engine. Emits:

```
reader:ready        { bookId, totalPages }
reader:pagechange   { page, spread, leafId, direction }
reader:turnstart    { direction }
reader:turnend      { direction, completed }
```

State is plain objects, no framework. The controller name is `reader`.

### 2. `paginate.js` — the paginator

Pure functions plus one DOM measurer.

Input: ordered leaves (`id`, `title`, `kind`, `html`, `href`) and a layout key.
Output: `Page[]`, each `{ index, leafId, startOffset, endOffset, nodes }`.

Algorithm:

1. Wait for `document.fonts.ready` and for every image in the current leaf to
   have `width`/`height` or an `aspect-ratio`. Never measure while fonts are
   swapping.
2. Build a hidden measuring page with the exact content box, typography, and
   `contain: layout size`. It is `position: fixed; visibility: hidden` and never
   in the accessibility tree.
3. Walk top-level blocks. For a text block, binary-search the character offset
   whose last client rect fits the content box. For an atomic block, measure
   whole.
4. Keep a heading with its next block. Do not leave fewer than two lines of a
   paragraph on either side of a break (widows and orphans). Split `pre` at line
   boundaries and tables at row boundaries; never split a figure, an image, or
   a blockquote shorter than a page.
5. A block taller than a page gets its own page and is scaled only if it is an
   image; code and tables keep their size and may overflow with a visible
   scroll affordance.
6. Clone the fitted nodes into the page. Store source offsets so a deep link or
   a search hit can resolve to a page. Never mutate the source content.
7. Paginate the current leaf first, then the next, yielding between leaves so
   the first spread paints before the rest of the book is measured. Pagination
   is cancellable and restarts on a layout-key change.

Layout key: `bookId + contentVersion + viewportWidth + viewportHeight +
pageScale + fontScale + theme`. Cache the page map in memory; optionally in
`sessionStorage` keyed by the same string. Do not cache HTML.

`contentVersion` is a digest the server computes over the ordered leaf ids and
their updated timestamps, so an edit invalidates the map.

### 3. `spread.js` — layout and mounting

Maps page indices to a spread (`[2n, 2n+1]` on desktop, `[n]` on mobile), mounts
at most the current spread ±2, and unmounts the rest. Reserve the page box
before content arrives so nothing shifts. Owns the cover and back cover.

### 4. `flip.js` — the turn engine

Interface:

```js
const engine = createFlipEngine(element, { slices, reducedMotion })
engine.begin({ direction, progress })
engine.drag({ direction, progress })
engine.complete()
engine.cancel()
engine.destroy()
```

Default engine: rigid CSS 3D. The turning leaf is one element with a front and
back face, `transform-origin` on the spine, rotated in `rotateY` inside a
`perspective: 2400px` stage, with `transform-style: preserve-3d` on the leaf.

Curl upgrade: the same leaf is divided into 8 vertical slices on desktop and 6
on mobile. Each slice receives a `rotateY` and a small `translateZ` so the page
follows a cylinder rather than a plane. The slices exist only while a turn is
in flight; at rest the page is a single flat element. If the engine detects two
consecutive frames over 24ms, it degrades to the rigid engine for the rest of
the session.

Shadows:

- A gutter shadow that deepens toward the spine.
- A cast shadow on the page beneath, moving with the leaf edge.
- A thin specular band just inside the curl.
- All gradients are pseudo-elements with `pointer-events: none`. No `filter`
  on text, ever.

Input:

- Pointer drag with `setPointerCapture`, axis lock after 6px, and a 1:1
  progression clamped to `[0, 1]`.
- Release completes at 28% or 0.45 px/ms; otherwise it snaps back over 220ms.
- Keyboard and click zones call the same `begin/complete` path.
- `touch-action: pan-y` on the book so vertical scroll survives; horizontal
  intent is claimed only after the axis lock.
- Turns are serialized. A new input during a turn is queued, never interleaved.

### 5. `a11y.js` — the honest layer

- At rest every visible page is a real `<article>` with `aria-label="Page N of
  M"`. Off-screen spreads are `inert` and `aria-hidden`.
- A polite live region announces `Page N of M`.
- Focus stays on the reader region across turns; `Tab` reaches only the current
  spread's links.
- The **Continuous** link is a real anchor to the long-document route and works
  with JavaScript disabled. The reader itself is progressive enhancement: the
  server-rendered first leaf is readable before the module loads.
- Reduced motion uses a 120ms crossfade. Forced colors and 200% zoom are tested,
  not assumed.

## Data contract

The shell embeds a JSON payload in a `<script type="application/json">` tag:

```json
{
  "book": { "id": 12, "title": "...", "author": "...", "theme": "blue" },
  "contentVersion": "sha256:...",
  "leaves": [
    { "id": 31, "kind": "section", "title": "...", "href": "/12/slug/31/slug", "html": "..." }
  ]
}
```

For books over 50 leaves, the shell embeds only the first three and exposes
`GET /books/:id/reader.json?after=:leafId` for the rest. The endpoint returns
the same shape and is public only for published books; signed-in staff may read
drafts. It sets `Cache-Control: private, max-age=60` for drafts and a public
cache keyed by `contentVersion` for published books.

No page manifest is sent from the server. Pagination is a function of the
viewport, and pretending otherwise produces drift.

## Static export

`Writebook::StaticExporter` gains a reader output for each published book:

- The book's `index.html` becomes the reader shell, with the JSON inlined.
- `reader.js`, `reader.css`, and the existing fonts are copied in; all paths
  relative.
- Leaf HTML is inlined for books up to 50 leaves; larger books write
  `reader.json` beside the page.
- The long-document pages remain in the export as `continuous.html` so the
  no-JS path and deep links survive.
- Images keep their existing copied blobs and relative URLs.

Acceptance: export to a directory, serve it with `python3 -m http.server`, open
a book, turn to page 10, reload, and land on page 10 with no console errors and
no requests to absolute Rails paths.

## Library order

A press does not shelve its books alphabetically. The library order becomes an
explicit, admin-controlled sequence that every surface follows: the signed-in
library, the public catalog, and the static export.

The current behavior is worth stating plainly: `Book.ordered` is
`order(:title)`, and there is no publication timestamp in the schema. The
backfill must reproduce that visible order exactly, so the upgrade changes
nothing until someone drags a book.

### Product

- Administrators get a **Reorder books** action in the library header, beside
  Export and Settings.
- It opens `GET /books/order`: the same arrangement view the book table of
  contents uses, applied to book plates. Drag to reorder, click to select,
  arrows to move, Shift+arrows to extend the selection, Space to enter move
  mode, Enter to apply, Escape to cancel.
- The view shows the library's own plates (cover, title, author, and a Draft
  badge for unpublished books), not a compact text list.
- Saving is optimistic: the DOM reorders immediately, then `POST /books/moves`
  persists `position` plus `id[]`. The page does not reload. A failed request
  restores the original order and says so.
- The order is global. Every member and every reader sees the same sequence.
  Per-user personal ordering is a non-goal.

### Data and model

- `books.position_score` float, not null, indexed with `id`.
- Backfill with `row_number() over (order by title, id)`, matching the old
  scope.
- `Book.positioned` orders by `position_score, id`.
- `Book.ordered` becomes an alias for `positioned`. Every existing call site
  already uses `ordered`, including `StaticExporter`, so the export and the
  result pages follow the manual order without further changes.
- New books append at the end. Deleting a book leaves a gap; gaps are fine, and
  the existing rebalance threshold handles pathological insertion.

### Reuse

The existing `arrangement` Stimulus controller, its keyboard map, and its
selection model are used unchanged. Only three things are new:

1. `Positionable` gains a `positioned_globally` mode: `Current.account` is the
   lock, `Book.all` the sibling set. Leaves keep their per-book parent.
2. `arrangement_tag` accepts a nil book and defaults its URL to
   `books_moves_url`, omitting the reading-progress data attributes.
3. The order view supplies the grid: `.position-relative` wrapper, the
   `arrangement` container, direct-child items carrying `data-id`, the drag
   layer, and the drag image.

The controller measures real rectangles, so a responsive grid works as well as
the TOC's list. It must not be reordered with the CSS `order` property, because
the selection model reads DOM order.

### Routes and access

```
GET  /books/order   books/orders#show     administrator only
POST /books/moves   books/moves#create    administrator only
```

Both use the existing `ensure_can_administer` guard. A non-administrator gets
403, not a hidden button. The move endpoint accepts the same payload as the
leaf moves endpoint (`position`, `id[]`) and returns `204`; unknown ids return
`422`.

### Tests

- Model: backfill matches title order; append goes last; move to start, middle,
  and end; rebalance keeps order; two reorders in a row are stable.
- Controller: administrator succeeds; member and anonymous are forbidden;
  unknown ids are rejected.
- System: open the order view, move a book with the keyboard, reload, confirm
  the new order. Confirm the entry point is absent for a member.
- Surfaces: the public library and the static export both list books in the
  manual order.

### Risks

- **Caching.** The library index is cached as `[ @books, signed_in? ]`. Moving a
  book updates its `updated_at`, which changes the collection key, but the
  milestone must prove it with a test rather than assume it.
- **Grid geometry.** The arrangement layer positions clones absolutely against
  the nearest `.position-relative` ancestor. The order view must provide one,
  and the item list must be the direct parent of the plates.
- **Two admins at once.** The move contract is last-write-wins. That is
  acceptable for a two-person press; a `library_version` with a `409` is a
  later refinement, not v1.
- **Backfill drift.** Running the backfill in Ruby in arbitrary order will
  scramble a library. Do it in SQL with an explicit `order by title, id`.
- **Do not sort published books separately.** The catalog is a subset of the
  same sequence; filtering must not re-sort it.

## Progress and deep links

- `?page=N` is authoritative. `N` is 1-based.
- The server does not know page boundaries, so it renders the shell and the
  client resolves `?page=` after pagination. If `N` exceeds the book, land on
  the last page and replace the URL.
- Progress records `{ leafId, startOffset, pageIndex, totalPages,
  contentVersion }`. If `contentVersion` differs, resolve by `leafId` and
  `startOffset`, not by page number.
- Search hits carry `leafId` and a text offset; the reader resolves the leaf,
  paginates it if needed, finds the page containing the offset, and flashes the
  highlight.
- A bookmark stores the same anchor shape, so it survives republication.

## Tooling

The fork tracks the 37signals house style, not upstream Writebook's pinned
tooling. That is deliberate; an upstream merge must not revert it.

- **Ruby**: the version in `.ruby-version` (3.4.7 on the fork today, 3.4.12 on
  upstream main), with `rubocop-37signals` from `razodin137/house-style`.
  `.rubocop.yml` inherits the gem's `rubocop.yml`; `rubocop-rails-omakase` is
  gone. Run `bin/rubocop`.
- **JavaScript**: Node 20.19 or newer (the machine has 26), ESLint 10, and
  `@37signals/eslint-config` from the same fork. The clone carries 0.1.0 while
  npm still serves 0.0.2, so the config is vendored into
  `vendor/house-style/eslint-config` and installed with a relative `file:` spec
  that also works in CI. `eslint.config.mjs` extends it and declares the
  `Turbo` global. Run `npm run lint`.
- **CSS**: there is no SCSS. The app ships plain CSS through Propshaft, so the
  fork's `stylelint-config-scss` does not apply and is not installed. Do not
  convert the stylesheets to SCSS just to satisfy a linter.
- **Runtime**: Rails and Ruby stay on the version the fork ships. This tooling
  update is linting, not a framework upgrade. A framework bump arrives through
  an upstream sync, never by hand.

The tooling is in place before milestone 01. A feature prompt that finds it
missing is running against the wrong checkout.

## Testing

- **Ruby**: `bin/rails test`. Cover the reader routes, draft access, JSON
  shape, `contentVersion` changes on edit, and the static export's reader
  files.
- **System**: `bin/rails test:system`. Open a book, turn forward with the
  keyboard, assert the second spread's text and the URL; open with `?page=7`
  and assert the page; assert the Continuous link works.
- **JavaScript**: `node --test test/javascript/reader`. Pure functions only:
  offset splitting, widow/orphan adjustment, spread mapping, progress anchor
  resolution, layout-key construction. The existing `package.json` already has
  `"type": "module"` and the lint tooling; add the `test` script, no bundler,
  no build step.
- **Visual**: no screenshot service. The turn is inspected in Safari, Chrome,
  and Firefox at 1440×900, 1024×768, 390×844, and with reduced motion.
- **Budgets**: reader JS ≤ 40KB gzipped; 300 pages paginated in ≤400ms on a
  2020 laptop; turns ≥55fps desktop and ≥30fps mobile; no layout shift after
  first paint.

## Milestones

One prompt per milestone, run in order. Each leaves the app shippable.

| File | Milestone | Demo |
| --- | --- | --- |
| `01-reader-shell.md` | Reader route, shell, cover, one static page; amend `design.md` | A published book opens as a closed cover and shows page one |
| `02-pagination.md` | Measuring paginator, page map, offsets, cache | A 300-page book splits correctly; resizing reflows |
| `03-turn.md` | Rigid 3D flip, drag, keyboard, click zones, shadows | A page turns under the pointer and lands flat |
| `04-spread.md` | Two-page spread, gutter, running heads, folios, mobile single page | Desktop reads as a spread; mobile as one page |
| `05-curl.md` | Segmented curl, frame-budget degradation | The page bends instead of flipping as a card |
| `06-navigation.md` | TOC insert, `?page=`, progress, resume, bookmarks | Reload lands on the same page; TOC jumps to a chapter |
| `07-a11y.md` | Inert off-screen pages, live region, focus, reduced motion, continuous link | Keyboard-only and screen-reader passes |
| `08-search.md` | Search hit to page, highlight flash | Searching a phrase opens the right page |
| `09-export.md` | Reader in the static export, `reader.json`, relative assets | Exported site turns pages offline from a plain HTTP server |
| `10-performance.md` | Chunked pagination, virtual spreads, preload policy, budgets | Open page one immediately on a 300-page book |
| `11-polish.md` | Theme variants, empty and error states, print CSS, docs | Every book theme reads correctly |
| `12-webgl-curl.md` | Optional WebGL drag enhancement behind the engine interface | Only if frame budgets still miss on target hardware |
| `13-book-position.md` | `position_score`, backfill, `Book.positioned`, `ordered` alias | New order persists; existing library unchanged until moved |
| `14-book-order-view.md` | Admin order route, reused arrangement view, moves endpoint | Drag and keyboard reorder the library plates |
| `15-book-order-surfaces.md` | Public catalog, static export, cache invalidation, docs | Imported order appears in the exported site too |
| `16-upstream-sync.md` | Merge `basecamp/writebook` main, keep fork tooling, re-run checks | Fork is current, green, and still has the static export |

`00-overview.md` is this spec; the runner skips step 0.

## Reconciling with upstream

Upstream `basecamp/writebook` moves, and the fork must not drift into a
month-old copy. At the time of writing the fork is 28 commits behind, 33 files,
mostly security and dependency work, plus a first-run singleton migration and
upload-path handling. That is small enough to merge, and it already touches two
files this work also touches: `books_controller.rb` and
`application_controller.rb`.

Sync twice:

1. **Baseline, before milestone 01.** Add `upstream`, fetch, merge
   `upstream/main` into `static-site-generator`, resolve conflicts, and run
   `bin/rails test`, `bin/rubocop`, and `npm run lint`. Commit the merge on its
   own so a bisect can find it. Build features on current upstream, not on a
   month-old fork.
2. **Final, milestone 16.** Repeat after the features land. This is the
   reconciliation the fork ships with.

Baseline done on 2026-11-05: 28 commits, Ruby 3.4.7 to 3.4.12, and one fork fix.
Upstream made the upload redirect path-only, so
`Writebook::StaticExporter#fetch_bytes` now keeps a relative `Location`
relative instead of calling `request_uri` on a `URI::Generic`. All four checks
pass. The remaining reconciliation is milestone 16.

Conflict policy:

- **Keep the fork's tooling.** Resolve `Gemfile`, `.rubocop.yml`,
  `package.json`, `eslint.config.mjs`, and `.gitignore` in the fork's favour.
  Take upstream's app gems, then re-run `bundle install`; do not restore
  `rubocop-rails-omakase` or a bundler.
- **Keep the fork's features.** The static-site generator, the reader, and the
  order view survive the merge. Upstream has no opinion on them.
- **Take upstream's security work.** Sanitizers, upload handling, CSP, and
  dependency bumps are the reason to sync. Do not hand-merge around them.
- **Take upstream's `.ruby-version`.** Install that Ruby before running the
  checks. If it is not available, stop and say so; do not pin back to an older
  Ruby just to get a green run.
- **Re-run the export tests.** Active Storage and sanitizer changes are the most
  likely to break the static export.
- **Do not carry the schema format bump by accident.** Running `db:prepare`
  under the Rails 8.2 alpha rewrites `schema.rb` to `ActiveRecord::Schema[8.2]`
  and sorts columns. Revert that incidental diff and let the next feature
  migration regenerate it, unless the merge is explicitly meant to adopt the
  new format.
- Never merge upstream inside a feature prompt, and never merge into a dirty
  tree.

## Guardrails for every prompt

- The repository is the only source of truth. Do not read another Writebook
  checkout, a build artifact, or a cached copy.
- One milestone per prompt. Touch the files the prompt names and nothing else.
- No new runtime npm dependency. No bundler. No TypeScript. No framework.
  Dev-only lint dependencies are allowed.
- JavaScript follows house style: double quotes, no semicolons, 2-space indent,
  no trailing commas, `const` by default, spaces inside array brackets, no space
  before call parentheses.
- Ruby follows `rubocop-37signals` from `razodin137/house-style`; the tooling
  milestone installs it. Do not add a second style config.
- Run `bin/rails test`, `bin/rubocop`, `npm run lint`, and, once it exists,
  `npm test` before claiming done. If a check cannot run, say so in the
  prompt's result.
- Do not reformat unrelated files. Do not "clean up" the old long-document
  route.

## Definition of done

- A published book opens as a book, turns with the pointer, and lands on real
  text.
- The same reader works in the static export with no Rails process.
- Keyboard, reduced motion, 200% zoom, and the Continuous fallback all work.
- Page links survive an edit and a new publication by resolving through the
  leaf anchor.
- The library order is explicit, administrator-controlled, and identical in
  the app and the static export.
- The reader adds ≤40KB gzipped JavaScript and does not regress the editing UI.
- `bin/rails test`, `bin/rubocop`, `npm run lint`, and `npm test` pass.

## Risks and gotchas

1. **Measuring before fonts.** `document.fonts.ready` is not enough if an image
   has no dimensions. Reserve intrinsic size or the page map will be wrong on
   the second visit.
2. **3D text blur.** Compositing a DOM page in 3D can soften glyphs in Safari
   and Chrome. Keep the resting page untransformed, avoid `filter` and
   `opacity` on text, and never leave a page on its own composited layer.
3. **`preserve-3d` and overflow.** `overflow: hidden` on an ancestor kills
   `preserve-3d` in Safari. The clip must live on a leaf-local wrapper.
4. **Gesture conflict.** A horizontal drag on a tall page must not fight the
   vertical scroll. Axis-lock, then claim.
5. **Deep-link drift.** Page numbers change; anchors do not. Resolve by
   `leafId` + offset and fall back to the leaf's first page.
6. **Export weight.** Inlining every leaf makes a large `index.html`. Switch to
   `reader.json` at 50 leaves and keep the first paint fast.
7. **Screen-reader duplication.** The reader and the continuous route must not
   both be exposed in the same document. The continuous route is a separate
   URL, not a hidden copy.
8. **Print.** The reader must print as the continuous document. Add print CSS
   that unmounts the prop and shows the full text, or point print at the
   continuous route.
9. **Search highlight offsets.** Existing highlights wrap text in `<mark>`.
   Offset math must run on the unhighlighted source, or pagination will split
   inside a mark.

---
description: Make the manual library order authoritative in every surface
---

## Guardrails

- Work in the application repository: the parent directory of this prompt pack
  (`..`). It is the only source of truth.
- Do exactly this task. Touch only the files named here.
- Do not add another ordering scope, a sort in Ruby, or a per-user order.
- Match the repo's Ruby style (`rubocop-rails-omakase`).
- Verify with `bin/rails test` and `bin/rubocop`. Report any check you could
  not run.

## Context

`Book.ordered` now means `positioned`. Verify, do not rewrite, these call sites:

- `app/controllers/books_controller.rb` — the library index
- `app/controllers/static_exports_controller.rb` — the export selector
- `app/views/static_exports/create.html.erb` — the exported-book list
- `lib/writebook/static_exporter.rb` — three `Book.published.ordered` sites

## Task

1. **Audit the call sites.** Confirm every one reads `Book.ordered` or
   `Book.published.ordered` and never re-sorts after loading. If a call site
   sorts in Ruby, remove that sort. Do not change the export's file names or
   directory layout.

2. **Cache.** The library index caches `[ @books, signed_in? ]`. A move updates
   `updated_at`, so the collection key should change. Add an integration test
   that reorders books, reloads the index, and asserts the rendered order
   changed. If it does not change, `touch` the moved books in
   `Books::MovesController` and re-run the test.

3. **Public catalog.** Add a test that a signed-out visitor sees the manual
   order and only published books, with no re-sorting. Put it beside the
   existing books controller tests.

4. **Static export.** Add a test that two published books appear in the
   exported menu in their manual order. Export into a temporary directory under
   `tmp/`; do not assert on absolute paths or timestamps. Confirm the same
   order in `test/lib/writebook/` if that suite already builds an export.

5. **Docs.** Add one sentence to `README.md` under "What's here": administrators
   can reorder the library, and the order carries into the static export. Do not
   rewrite the README.

6. **Upgrade check.** If a copy of the pre-change development database is
   available, run `bin/rails db:prepare` against it and confirm the backfill
   matches the old title order. If not, say so in the result instead of
   claiming it.

## Gotchas

- The static export runs inside a transaction. Do not reorder anything during
  the export; it reads the committed order.
- `StaticExportsController#show` builds its book selector from `Book.ordered`
  and must match the exported order exactly.
- The public library and the signed-in library share one order. Do not sort
  published books to the front, and do not filter before ordering.
- Cache keys use `updated_at`. A move that does not touch the record leaves the
  old order cached. Assert it rather than assume it.
- The book partial caches each plate individually; reordering does not change a
  plate's contents, only its position. That is fine. Do not purge those caches.

## Done when

- `bin/rails test` and `bin/rubocop` pass.
- A reversed order is visible in the app and in an exported directory.
- No call site re-sorts books after `Book.ordered`.
- The README note is the only prose change.

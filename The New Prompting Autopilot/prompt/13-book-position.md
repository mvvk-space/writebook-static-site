---
description: Add position_score and an explicit order to books
---

## Guardrails

- Work in the application repository: the parent directory of this prompt pack
  (`..`). It is the only source of truth. Do not read another checkout, a
  cached copy, or the archived prompt packs.
- Do exactly this task. Touch only the files named here.
- Match the surrounding Ruby. The repo uses `rubocop-rails-omakase`; keep its
  spaced array literals (`[ :a, :b ]`).
- If an anchor named below is missing, or the change would alter behaviour
  beyond this task, write the reason to `.scratch/BLOCKED-13-book-position` and
  stop. Do not improvise.
- Verify with `bin/rails test` and `bin/rubocop`. Run the full suite at most
  twice.

## Context

`Book.ordered` is `order(:title)` today and is used by the library index, the
static export controller, the export result view, and `StaticExporter` in three
places. The library has no publication timestamp, so title order is the only
existing order. This task makes order a column, without changing what anyone
sees until an administrator moves a book.

## Task

### 1. Migration

Create `db/migrate/<timestamp>_add_position_score_to_books.rb`:

- `add_column :books, :position_score, :float`
- backfill every row in SQL with `row_number() over (order by title, id)`
- `change_column_null :books, :position_score, false`
- `add_index :books, [ :position_score, :id ]`

`down` removes the index and the column. `bin/rails db:migrate:redo` must pass.
Do not order the backfill by `created_at`; that would reorder existing
libraries.

### 2. Positionable

In `app/models/concerns/positionable.rb`, make the lock injectable:

- `positioned_within` defines `positioning_lock` as a callable that locks
  `positioning_parent`.
- Add `positioned_globally(lock:)` for a set with no parent row. It defines
  `positioning_lock`, `all_positioned_siblings` (`self.class.positioned`), and
  `other_positioned_siblings`.
- `with_positioning_lock` calls `positioning_lock` in both modes.

Keep `Leaf` and its `positioned_within :book` call unchanged. Do not add
`account_id` to books.

### 3. Book

In `app/models/book.rb`:

- include `Positionable`
- `positioned_globally lock: ->(&block) { Current.account.with_lock(&block) }`
- replace `scope :ordered, -> { order(:title) }` with
  `scope :ordered, -> { positioned }`

Do not rename `ordered`; the export depends on it.

### 4. Fixtures

Add a `position_score` to each record in `test/fixtures/books.yml` so the
not-null constraint holds. Keep `handbook` before `manual`, matching the old
title order.

### 5. Tests

In `test/models/book_test.rb`:

- `Book.ordered` follows `position_score`, not title. Reorder the fixtures so
  the two orders differ.
- A new `Book.create!` appends after the last book.
- `move_to_position` moves a book to the start, the middle, and the end.
- Two consecutive moves leave a stable order.
- `Book.positioned` and `Book.ordered` return the same sequence.

Use existing fixtures; do not add a fixture file.

## Gotchas

- `around_create :insert_at_default_position` now runs for every book and
  locks `Current.account`. The account fixture exists in tests. If
  `Current.account` is nil, let the create proceed without a lock instead of
  raising; the first run creates the account before any book.
- `rebalance_positions` uses a window function. SQLite supports it; do not
  rewrite it in Ruby.
- The migration backfill and the scope must agree exactly. If they diverge, an
  upgraded library reorders itself on its own.
- `Book.ordered` must stay the single ordering scope. Do not add `by_position`
  or sort in Ruby at the call sites.

## Done when

- `bin/rails test` passes.
- `bin/rubocop` passes.
- `bin/rails db:migrate:redo` passes.
- `Book.ordered` follows `position_score`, and a fresh book lands last.

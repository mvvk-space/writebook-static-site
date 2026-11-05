---
description: Reconcile the fork with basecamp/writebook main
---

## Guardrails

- This is a merge, not a feature. Do not add reader or book-order code.
- Work on the fork's `static-site-generator` branch, from a clean tree. If
  either is not true, stop.
- Create a merge branch (`sync/upstream-YYYYMMDD`). Never merge on `main`.
- Resolve conflicts file by file. Never run `git checkout --ours` or
  `--theirs` across a tree.
- If a conflict is not covered by the policy below, write the paths and the
  reason to `.scratch/BLOCKED-16-upstream-sync` and stop. Do not guess.
- Verify with `bin/rails test`, `bin/rubocop`, `npm run lint`, and
  `bin/rails test:system`.

## Context

- Upstream: `https://github.com/basecamp/writebook.git`, branch `main`.
- Fork branch: `static-site-generator`.
- A baseline sync was done before milestone 01. This is the final one; upstream
  may have moved since.
- The fork adds the static-site generator, the page-turn reader, and the
  library order. Upstream has no opinion on any of them.
- The fork replaces upstream's lint tooling with the house style. That is
  deliberate and must survive the merge.

## Task

1. `git fetch upstream main`. Report how many commits are new.
2. `git switch -c sync/upstream-$(date +%Y%m%d)`.
3. `git merge --no-ff upstream/main`.
4. Resolve by policy:
   - **`Gemfile`**: take upstream's application gems, keep
     `rubocop-37signals` from `razodin137/house-style`. Drop
     `rubocop-rails-omakase` if it reappears.
   - **`Gemfile.lock`**: take upstream's app versions, then run
     `bundle install` under the Ruby named in `.ruby-version`.
   - **`.rubocop.yml`**: keep
     `inherit_gem: { rubocop-37signals: rubocop.yml }`.
   - **`package.json`, `package-lock.json`, `eslint.config.mjs`**: keep the
     fork's. Do not remove the `file:` house-style dependency or the `Turbo`
     global.
   - **`.gitignore`**: take the union. Keep `/node_modules`.
   - **`.ruby-version`**: take upstream's. Install that Ruby before running the
     checks. If it is unavailable, stop and report it; do not downgrade to get
     a green run.
   - **`app/controllers/application_controller.rb`**: take upstream's new
     concerns. The fork adds nothing there.
   - **`app/controllers/books_controller.rb`**: take upstream's
     `uploaded_files_only` change. The order feature changes only the index
     scope and a view, not `book_params`.
   - **`config/routes.rb`**: keep upstream's routes and the fork's `books/order`
     and `books/moves` routes. Both must survive.
   - **Reader, order, and static-export files**: keep the fork's versions. If
     upstream changed a file the reader patches, re-apply the reader change by
     hand and say so.
5. If `db/schema.rb` changed, run `bin/rails db:prepare` and confirm the new
   migration applies.
6. Run the checks. If the full suite flakes on Active Storage file errors,
   re-run the failing file alone before deciding it is real.
7. Report the merge commit, the files resolved, the new Ruby version, and any
   check that failed.

## Gotchas

- Upstream's sanitizer and upload changes are the point of the sync. Do not
  hand-merge around them to keep an older shim.
- The static export reads Active Storage directly. Run
  `test/lib/writebook/static_exporter_test.rb` and
  `test/controllers/static_exports_controller_test.rb` explicitly after the
  merge.
- The reader adds routes and a JSON endpoint; a clean `routes.rb` diff is not a
  sign the merge is done. Run `bin/rails routes | grep -E "read|reader|books/(order|moves)"`.
- Do not merge upstream into a dirty tree, and do not fold the merge into a
  feature commit. A bad merge should be one `git revert` away.

## Done when

- `bin/rails test`, `bin/rubocop`, `npm run lint`, and `bin/rails test:system`
  pass.
- The static export still runs and contains the reader.
- `git log --oneline --merges -1` shows the synchronization merge.

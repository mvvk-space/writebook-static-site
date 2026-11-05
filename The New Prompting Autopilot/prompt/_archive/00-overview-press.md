---
description: Product spec and milestone map for Writebook Press
---

# Writebook Press

Working name for the application built on the `writebook-edit` fork (Rails 8,
SQLite). The fork already writes books and exports a self-contained static site.
Writebook Press adds the work that happens *before* publishing: staffing,
review, annotation, revision control, and a public edition that cannot change
under a reader's feet.

## The problem

Writebook assumes one trusted author per install. The moment a small press puts
three people on one book, the model breaks:

- Everyone who can open the book can edit it. There is no author who may draft
  but not approve, and no reviewer who may comment but not touch the prose.
- "Published" is a boolean, not an edition. Editing a published book silently
  changes what readers see.
- `Edit` records superseded content but not who changed it or why, and it
  coalesces changes inside a ten-minute window with no way to force a
  checkpoint.
- There is nowhere to say "this paragraph is wrong" without editing the
  paragraph.

## Product statement

Writebook Press is a production desk for a small press. A book moves through a
named editorial lifecycle; every change is attributable and reversible; review
comments are anchored to the passage they are about; and publishing freezes an
artifact that readers see, while the working copy keeps moving.

Four promises:

1. **Every book has a staff and a stage.**
2. **Every change is attributable and reversible.**
3. **Every review comment points at the text it is about.**
4. **What readers see is a frozen publication, not the working copy.**

## Personas and jobs

| Persona | Instance role | Book role | Job to be done |
| --- | --- | --- | --- |
| Press owner | `administrator` | `publisher` | Staff books, approve publication, manage the install |
| Editor | `member` | `editor` | Run review, comment, request changes, approve leaves |
| Author | `member` | `author` | Draft and revise assigned leaves, answer comments |
| Reviewer | `member` | `author` (read + comment only during review) | Read a draft and leave anchored feedback |
| Reader | none / `member` | `reader` or public | Browse the catalog, read published editions, keep progress |
| Operator | `administrator` | any | Deploy, configure export targets, watch failed jobs |

Reviewers are not a separate table. An author on a book in review may comment
but the leaf lock keeps them out of the editor until the review round is
resolved. If that proves too subtle in practice, a dedicated `reviewer` level is
the fallback, not the starting point.

## Domain model

Existing tables stay; this is an extension, not a rewrite.

### Changed

- `accesses.level` gains `author` and `publisher`. Order is
  `reader < author < editor < publisher`. `editor` keeps its current meaning
  ("may edit the book"); `publisher` adds the right to publish and archive.
- `books` gains `stage` (`drafting`, `in_review`, `changes_requested`,
  `approved`, `published`, `archived`), `stage_changed_at`, and
  `approved_at`. Keep `published` as a derived convenience for the public
  query; `stage` is the source of truth.
- `leaves` gains `review_state` (`draft`, `in_review`, `changes_requested`,
  `approved`) and `reviewed_at`. `status` (`active`/`trashed`) is unchanged.
- `edits` gains `user_id`, `summary`, and `origin` (`autosave`, `checkpoint`,
  `restore`). The `revision`/`trash` action stays.

### New

- `leaf_assignments` — `leaf_id`, `user_id`, unique per pair. Scopes an author
  to the leaves they may edit.
- `review_requests` — `book_id`, optional `leaf_id` (null means book-level),
  `requester_id`, `reviewer_id`, `state` (`open`, `approved`,
  `changes_requested`, `cancelled`), `due_on`, `note`, timestamps. One open
  request per leaf.
- `comments` — `leaf_id`, `user_id`, optional `parent_id` (one level of
  replies), `body`, `quoted_text`, `anchor_start`, `anchor_end`,
  `resolved_at`, timestamps. Anchors store character offsets **and** the quoted
  text; the quote is the recovery key when offsets drift.
- `publications` — `book_id`, `published_by_id`, `format` (`html`,
  `markdown`), `state` (`building`, `ready`, `failed`), `manifest` (JSON:
  leaf ids, titles, checksums), `artifact_path`, `byte_size`, `checksum`,
  `error`, timestamps. A book has at most one `ready` publication per format;
  publishing again supersedes it.
- `imports` — `book_id`, `kind` (`markdown`, `epub`), `source_name`,
  `state` (`queued`, `running`, `succeeded`, `failed`), `log`, timestamps.
- `notifications` — `user_id`, `notifiable_type`/`notifiable_id`, `kind`,
  `read_at`.
- `reading_progress` — `user_id`, `book_id`, `leaf_id`, `percent`, timestamps,
  unique per user/book.
- `deploy_targets` — `account_id`, `name`, `kind` (`webhook`, `s3`), `endpoint`,
  `secret_ciphertext`, `active`. Secrets encrypted with Active Record
  encryption; never rendered back to the browser.

No multi-tenancy. `Account` remains the press.

## Roles and permissions

| Capability | reader | author | editor | publisher | administrator |
| --- | --- | --- | --- | --- | --- |
| Read working copy | ✓ | ✓ | ✓ | ✓ | ✓ |
| Read published edition | ✓ | ✓ | ✓ | ✓ | ✓ |
| Comment on a leaf | | ✓ (any stage) | ✓ | ✓ | ✓ |
| Edit a leaf | | ✓ when `drafting` or `changes_requested` and assigned | ✓ | ✓ | ✓ |
| Create/trash leaves | | | ✓ | ✓ | ✓ |
| Request review | | ✓ | ✓ | ✓ | ✓ |
| Approve / request changes | | | ✓ | ✓ | ✓ |
| Publish / unpublish / archive | | | | ✓ | ✓ |
| Staff a book | | | | ✓ | ✓ |
| Manage deploy targets | | | | | ✓ |

Rules enforced server-side in controllers and models; views only hide controls
they already know are forbidden.

- An author may edit only leaves they are assigned to. Assignment is
  `comments`-free: a new `leaf_assignments` join table (`leaf_id`, `user_id`)
  scoped to the book's staff. Untouched leaves without an assignment belong to
  whoever holds `editor`.
- `everyone_access` keeps its meaning for readers. It never grants editing.
- An administrator is not implicitly a book editor; they may administer the
  install without editing prose. The UI must say so rather than silently
  granting.

## Editorial lifecycle

Book stages and the only legal transitions:

```
drafting ──request review──▶ in_review ──changes──▶ changes_requested
   ▲                             │                        │
   └────────── resume ───────────┘                        │
                                 │ approve                │ resubmit
                                 ▼                        ▼
                              approved ──publish──▶ published ──archive──▶ archived
                                 ▲                                          │
                                 └──────────── unpublish ◀──────────────────┘
```

- **Request review** requires at least one active leaf and an assigned editor
  or publisher. It flips requested leaves to `in_review` and files a
  `review_request` per leaf.
- **Approve** is per leaf. The book may reach `approved` only when every active
  leaf is `approved`. A publisher may override with a written reason; the
  override is stored on the book and shown on the publication record.
- **Publish** requires `approved` (or an override) and produces a `publication`
  row. It never mutates the working copy.
- **Unpublish** moves a published book back to `approved`; the last ready
  publication stays on disk until a new one supersedes it, so readers get a
  clear "withdrawn" page rather than a 404 during the transition.
- Trashing a leaf during review cancels its open request and drops it from the
  approval gate. Restoring it returns it to `draft`.

## Key flows

### 1. Staff a book

Publisher opens **Staff**, searches active users, and sets a level. The server
writes `accesses` rows and recomputes `everyone_access` readers. Removing an
author with open review requests reassigns those requests to the book's editor
or leaves them unassigned and flagged, never orphaned silently.

### 2. Draft, review, revise

Author edits an assigned leaf. Autosave writes an `edit` only if the content
actually changed and the ten-minute window has elapsed. **Save checkpoint**
forces an `edit` with a summary and the author's id. **Request review** files a
request and notifies the reviewer. The reviewer reads the leaf, leaves anchored
comments, then either approves or requests changes with a note. Requesting
changes flips the leaf, unlocks it for the author, and notifies them. The author
sees the comments in the margin, revises, and resubmits. Approval is the editor's
act, not the author's.

### 3. Comment on a passage

Select text in a published or in-review leaf, press the comment affordance, and
write. The server stores offsets plus the quote and a short prefix/suffix
context. On render, the client re-locates the quote; if the offsets no longer
match, it searches the current body for the quote. If the quote is gone, the
comment falls back to a leaf-level note marked **outdated**. Comment threads are
one reply deep. Resolving a thread hides it from the margin but keeps it in the
history.

### 4. History, diff, restore

The leaf history is the existing `Edit` chain. Show each revision with author,
time, summary, and a word-level diff against its predecessor. **Restore** copies
the old leafable into a new revision and a new edit, attributed to the person
restoring, with `origin: restore` and a summary naming the source revision. Never
rewrite history in place. Restoring attachments reuses the blob; do not duplicate
the file on disk.

### 5. Publish an edition

Publishing enqueues a job. The job runs the fork's existing static exporter
against the book (and, for a whole-library publish, every approved book), writes
the artifact, computes a manifest with per-leaf and per-blob checksums, and marks
the publication `ready`. Failure marks it `failed` with the log attached and
leaves the previous ready publication serving readers. The result page shows the
edition, the format, the leaf count, and the deploy state. Publishing is
idempotent: publishing an unchanged approved book produces the same checksum and
does not create a second ready row.

### 6. Read a published edition

The public catalog lists books with a ready publication, not every `published`
book. A book's public route serves the frozen artifact. Reading progress and
bookmarks attach to the edition, so a later edition does not corrupt a reader's
place: progress is stored as a leaf id and a percentage, and the reader sees a
"this edition changed" notice when the leaf no longer exists.

### 7. Import a manuscript

**Import** accepts a Markdown folder (`.zip`) or an EPUB. Parse front matter with
`front_matter_parser`; map `#` to sections and the next heading levels to leaves;
copy in-body images into Active Storage; keep the original filenames in the
manifest. EPUB parsing uses `rubyzip`, already in the Gemfile. An import creates
a new book in `drafting`, never merges into an existing one. A dry-run preview
lists the proposed tree and any unresolved images before anything is written.

### 8. Notify

In-app notifications for review requested, changes requested, leaf approved,
comment reply, publication ready, and publication failed. Email is a later
milestone and must respect a per-user preference. Every notification links to
the exact object; no digest-only mail.

## Non-goals

- Real-time co-editing or CRDTs. Last write wins with `lock_version` and a
  visible conflict notice.
- Payments, subscriptions, or a hosted multi-tenant service.
- EPUB *output*. Import only.
- A second search engine. Extend the existing `Leaf::Searchable` scopes.
- Full internationalization. Copy stays English; dates and numbers use Rails
  defaults.
- A native app. The existing PWA surface is enough.

## Constraints

- Rails 8, SQLite, Minitest with fixtures, importmap and Stimulus. Do not add a
  JS build step.
- Follow `AGENTS.md`: existing fixtures, `_path` helpers,
  `assert_in_body`/`assert_not_in_body`.
- RuboCop via the fork's existing `rubocop-rails-omakase` config. Do not
  introduce a second style config.
- No new gem without a note in the prompt that adds it, and no gem that needs a
  background service beyond the existing Redis/Resque.
- Migrations must be reversible and must backfill existing rows. A fresh
  `bin/rails db:prepare` and an upgrade from the pre-change schema must both
  work.
- Public routes must not leak drafts. The publication lookup, not the `published`
  boolean, is the gate.

## Milestones

Each milestone is one prompt in this directory and must leave the app
runnable, tested, and committed.

| File | Milestone | Demo |
| --- | --- | --- |
| `01-roles.md` | Extend access levels, permissions, staffing UI | Three people with three different capabilities on one book |
| `02-review.md` | Leaf review states, review requests, book stage machine | Author requests review; editor approves one leaf |
| `03-comments.md` | Anchored comments, threads, resolve, margin UI | Comment survives a paragraph edit and re-anchors |
| `04-history.md` | Edit attribution, checkpoint, diff, restore | Restore an old paragraph without losing the newer one |
| `05-publication.md` | Publication rows and the publish job | Publish freezes an edition; keep editing the working copy |
| `06-reader.md` | Catalog and reading routes from publications | Reader sees the edition, not the draft |
| `07-import.md` | Markdown and EPUB import with preview | Import a ten-chapter manuscript into a draft book |
| `08-notifications.md` | In-app notifications and preferences | Reviewer gets a link to the exact leaf |
| `09-deploy.md` | Deploy targets, webhooks, retries | Publish posts a signed webhook to a test receiver |
| `10-polish.md` | Activity feed, empty states, accessibility, docs | Press owner can explain what happened last week |

`00-overview.md` is this spec. Every later prompt repeats the shared
guardrails: one job, exact files, tests first where practical, no unrelated
reformatting, and a green `bin/rails test` plus `bin/rubocop` before commit.

## Definition of done

- `bin/rails test` passes.
- `bin/rubocop` passes with the project's existing config.
- `bin/rails db:prepare` succeeds on an empty database and on a copy of the
  current development database.
- Every new public route has a test proving drafts are unreachable.
- Publishing and importing are jobs with retry-safe, idempotent behaviour.
- No new N+1 queries in the catalog, book, and leaf index paths.
- Seeded demo data exercises one book in every stage.

## Risks and gotchas

1. **The ten-minute edit window.** `Leaf::Editable` coalesces edits. Publication
   must snapshot the *current* leafable, not the last `Edit`. A restore must not
   be swallowed by the window; `origin: restore` bypasses coalescing.
2. **Anchor drift.** Offsets are hints. The quote is the contract. Never show a
   comment against the wrong paragraph; degrade to "outdated" instead.
3. **Blob lifecycle.** Revisions share blobs. Purging a superseded leafable must
   not delete a blob another revision or a publication still references.
4. **`everyone_access`.** It currently inserts reader accesses for every active
   user. Staffing changes must recompute it without dropping explicit editors.
5. **Existing data.** Backfill `stage` from `published`, and `review_state` to
   `approved` for active leaves in already-published books. Do not silently
   reopen old books.
6. **Export cost.** The whole-library export is not a request-cycle operation.
   Run it in the job, stream progress, and never hold a transaction open across
   file I/O.
7. **Permission tests.** Test the negative case first: a reader posting to an
   edit route, an author approving their own leaf, a publisher of another book.

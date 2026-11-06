# Writebook (static site generator fork)

Instantly publish your own books on the web for free, no publisher required.

This is a fork of [basecamp/writebook](https://github.com/basecamp/writebook) that adds a **static site generator**: export the public library to a self-contained static HTML site you can host anywhere — no Rails process, login, or editing machinery. It also exports markdown and one **EPUB** e-book per book, plus a print view and one **PDF** per book. See [STATIC_SITE_GENERATOR.md](./STATIC_SITE_GENERATOR.md) for details.

**Repository:** [mvvk-space/writebook](https://github.com/mvvk-space/writebook)

## What's here

- A Rails app (the Writebook book-publishing platform) with a Dockerfile and Procfile for deployment
- The static-site-generator fork feature: renders the public library — the menu of books, every book's table of contents, and every leaf — to a self-contained static HTML directory. All CSS/JS assets and image binaries (covers, in-body uploads, ActiveStorage pictures) are copied in.
- Markdown and EPUB exports: one flat markdown directory per book, or one standards-based `.epub` e-book per book with chapters, a table of contents, the cover, and images embedded.
- Print and PDF: a print-optimised page for every book (print it from the browser) and one print-ready PDF per book from the export admin page or the command line.
- `AGENTS.md`, `CONTRIBUTING.md`, and upstream docs (MIT licensed)

## Quick start

```sh
bin/setup    # or use Docker
bin/dev
```
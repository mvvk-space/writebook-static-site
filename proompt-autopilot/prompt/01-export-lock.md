Your job is to go in and fix the browser exports here to this Ruby on Rails app.

Pressing a book's EPUB export dies with a locked database: the export holds a write transaction while it renders, so the next request waits on it. HTML, markdown, EPUB and PDF all have to download from the running server, one after another, for one book and for the whole library.

Done is when bin/rails test runs clean and so do house-style lints

/home/mrjohn/Work/tries/2026-11-03-house-style/house-style

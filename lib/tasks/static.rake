namespace :static do
  desc "Generate a static HTML site from published books into DIR (default: tmp/static-site). " \
       "Set STATIC_HOST for absolute URLs; STATIC_ALL=1 to include unpublished books."
  task :generate, [ :dir ] => :environment do |_task, args|
    dir = args[:dir] || "tmp/static-site"
    host = ENV.fetch("STATIC_HOST", "example.com")

    if ENV["STATIC_ALL"] == "1"
      # Temporarily publish every book so the exporter renders it, then roll the
      # change back so the live database is left untouched.
      Book.transaction do
        Book.where(published: [ false, nil ]).update_all(published: true)
        Writebook::StaticExporter.new(dir, host: host, verbose: true).call
        raise ActiveRecord::Rollback
      end
    else
      Writebook::StaticExporter.new(dir, host: host, verbose: true).call
    end
  end

  desc "Generate a markdown-only export from published books into DIR (default: tmp/static-site). " \
       "One flat directory per book: position-numbered front-matter .md files, an index.md " \
       "linking them, and in-body upload images copied in. STATIC_ALL=1 to include unpublished books."
  task :markdown, [ :dir ] => :environment do |_task, args|
    dir = args[:dir] || "tmp/static-site"

    if ENV["STATIC_ALL"] == "1"
      Book.transaction do
        Book.where(published: [ false, nil ]).update_all(published: true)
        Writebook::StaticExporter.new(dir, verbose: true, format: "markdown").call
        raise ActiveRecord::Rollback
      end
    else
      Writebook::StaticExporter.new(dir, verbose: true, format: "markdown").call
    end
  end

  desc "Generate one EPUB per published book into DIR (default: tmp/static-site). " \
       "Each EPUB carries the book's pages as chapters, a linked table of contents, " \
       "and its cover and images. STATIC_ALL=1 to include unpublished books."
  task :epub, [ :dir ] => :environment do |_task, args|
    dir = args[:dir] || "tmp/static-site"

    if ENV["STATIC_ALL"] == "1"
      Book.transaction do
        Book.where(published: [ false, nil ]).update_all(published: true)
        Writebook::StaticExporter.new(dir, verbose: true, format: "epub").call
        raise ActiveRecord::Rollback
      end
    else
      Writebook::StaticExporter.new(dir, verbose: true, format: "epub").call
    end
  end

  desc "Generate one print-ready PDF per published book into DIR (default: tmp/static-site). " \
       "Each PDF carries a title page, a table of contents, and every page in reading " \
       "order. Requires Chromium (set CHROMIUM_PATH if it isn't on PATH). " \
       "STATIC_ALL=1 to include unpublished books."
  task :pdf, [ :dir ] => :environment do |_task, args|
    dir = args[:dir] || "tmp/static-site"

    if ENV["STATIC_ALL"] == "1"
      Book.transaction do
        Book.where(published: [ false, nil ]).update_all(published: true)
        Writebook::StaticExporter.new(dir, verbose: true, format: "pdf").call
        raise ActiveRecord::Rollback
      end
    else
      Writebook::StaticExporter.new(dir, verbose: true, format: "pdf").call
    end
  end
end

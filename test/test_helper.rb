ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The static exporter writes to a real directory on disk. Parallel workers are
# separate processes sharing tmp/, so one worker's export or teardown would
# clobber another's mid-test. Give every worker its own export root; the hook
# only runs when parallel tests actually fork, so single-process runs keep the
# default tmp/static-site (see StaticExportsController#static_dir).
ActiveSupport::TestCase.parallelize_setup do |worker|
  Rails.application.config.x.static_export_root = Rails.root.join("tmp/static-site-test-#{worker}")
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include SessionTestHelper

    # Tests assert against the shipped provider table, so a per-install
    # WRITEBOOK_EMBED_PROVIDERS in the shell must not leak in — nor out.
    setup { @embed_providers_before = ENV.delete("WRITEBOOK_EMBED_PROVIDERS") }
    teardown { ENV["WRITEBOOK_EMBED_PROVIDERS"] = @embed_providers_before }
  end
end

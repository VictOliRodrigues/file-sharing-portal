ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    # Shared password for every user fixture. Kept above the minimum length so
    # that fixtures do not accidentally depend on a weaker policy.
    TEST_PASSWORD = "correct horse battery staple"

    def teardown
      # Active Storage writes into tmp/storage during tests.
      ActiveStorage::Blob.services.fetch(:test).delete_prefixed("") if defined?(ActiveStorage)
    rescue StandardError
      nil
    end
  end
end

module ActionDispatch
  class IntegrationTest
    # Signs a user in through the real sign in form, so tests exercise the same
    # code path as a browser would.
    def sign_in_as(user, password: ActiveSupport::TestCase::TEST_PASSWORD)
      post sign_in_path, params: { email_address: user.email_address, password: password }
      user
    end

    def sign_out
      delete sign_out_path
    end

    # Builds an uploaded file without touching the filesystem.
    def uploaded_file(filename: "report.txt", content: "hello world", content_type: "text/plain")
      Rack::Test::UploadedFile.new(
        StringIO.new(content), content_type, original_filename: filename
      )
    end
  end
end

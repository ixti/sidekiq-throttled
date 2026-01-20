# frozen_string_literal: true

appraise "sidekiq-8.0.x" do
  group :test do
    gem "sidekiq", "~> 8.0.0"

    # Sidekiq Pro license must be set in global bundler config
    # or in BUNDLE_GEMS__CONTRIBSYS__COM env variable
    if Bundler.settings["gems.contribsys.com"]&.include?(":")
      source "https://gems.contribsys.com/" do
        gem "sidekiq-pro", "~> 8.0.0"
      end
    end
  end
end

appraise "sidekiq-8.1.x" do
  group :test do
    gem "sidekiq", "~> 8.1.0"

    # Sidekiq Pro license must be set in global bundler config
    # or in BUNDLE_GEMS__CONTRIBSYS__COM env variable
    if Bundler.settings["gems.contribsys.com"]&.include?(":")
      source "https://gems.contribsys.com/" do
        gem "sidekiq-pro", "~> 8.1.0"
      end
    end
  end
end

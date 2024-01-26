# frozen_string_literal: true

appraise "sidekiq-7.0.x" do
  group :test do
    gem "sidekiq", "~> 7.0.0"

    # Sidekiq Pro license must be set in global bundler config
    # or in BUNDLE_GEMS__CONTRIBSYS__COM env variable
    install_if "-> { Bundler.settings['gems.contribsys.com']&.include?(':') }" do
      source "https://gems.contribsys.com/" do
        gem "sidekiq-pro", "~> 7.0.0"
      end
    end
  end
end

appraise "sidekiq-7.1.x" do
  group :test do
    gem "sidekiq", "~> 7.1.0"

    # Sidekiq Pro license must be set in global bundler config
    # or in BUNDLE_GEMS__CONTRIBSYS__COM env variable
    install_if "-> { Bundler.settings['gems.contribsys.com']&.include?(':') }" do
      source "https://gems.contribsys.com/" do
        gem "sidekiq-pro", "~> 7.1.0"
      end
    end
  end
end

appraise "sidekiq-7.2.x" do
  group :test do
    gem "sidekiq", "~> 7.2.0"

    # Sidekiq Pro license must be set in global bundler config
    # or in BUNDLE_GEMS__CONTRIBSYS__COM env variable
    install_if "-> { Bundler.settings['gems.contribsys.com']&.include?(':') }" do
      source "https://gems.contribsys.com/" do
        gem "sidekiq-pro", "~> 7.2.0"
      end
    end
  end
end

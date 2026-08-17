require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DynamicFlexMessage
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Nothing is attached or uploaded here, so there are no variants to
    # generate. Saying so is what keeps Active Storage from asking for an
    # image library the demo would never call.
    config.active_storage.variant_processor = :disabled

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    # The community this answers about is in Taipei, and so is every event time
    # the feeds carry. Left at UTC, "today" turns over eight hours late — an
    # event on tonight's calendar would be read as tomorrow's for the whole of a
    # Taipei morning. Rows are still stored in UTC; this is the zone they are
    # read and reasoned about in.
    config.time_zone = "Asia/Taipei"
  end
end

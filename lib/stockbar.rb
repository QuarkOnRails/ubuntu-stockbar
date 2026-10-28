# frozen_string_literal: true

# stdlib only outside ui.rb: the service runs ruby by absolute path, without rvm or bundler
module Stockbar
  VERSION = "1.0.0"
  ROOT = File.expand_path("..", __dir__)
  SERVICE = "stockbar.service"
  UUID = "stockbar@quarkonrails.github.io"
  URL = "https://github.com/QuarkOnRails/ubuntu-stockbar"

  class Error < StandardError; end
  class NotFound < Error; end
  class HTTPError < Error; end
end

require_relative "stockbar/paths"
require_relative "stockbar/atomic_file"
require_relative "stockbar/runner"
require_relative "stockbar/http"
require_relative "stockbar/models"
require_relative "stockbar/config"
require_relative "stockbar/cnbc"
require_relative "stockbar/formatter"
require_relative "stockbar/cache"
require_relative "stockbar/updater"
require_relative "stockbar/daemon"
require_relative "stockbar/setup"
require_relative "stockbar/table"
require_relative "stockbar/views"
require_relative "stockbar/banner"
require_relative "stockbar/cli"

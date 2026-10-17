# frozen_string_literal: true

require "stockbar"
require "minitest/autorun"
require "stringio"
require "tmpdir"

module TestHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)
  ENABLED_EXTENSIONS = %w[gsettings get org.gnome.shell enabled-extensions].freeze
  IS_ENABLED = %w[systemctl --user is-enabled stockbar.service].freeze
  START_SERVICE = %w[systemctl --user enable --now stockbar.service].freeze
  # right after apt install: our extension not enabled yet, unit installed but disabled
  FRESH_INSTALL = {
    ENABLED_EXTENSIONS => "@as []\n",
    %w[gsettings get org.gnome.shell disabled-extensions] => "@as []\n",
    IS_ENABLED => "disabled\n"
  }.freeze

  def fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, name)))
  end

  def in_sandbox
    Dir.mktmpdir("stockbar-test") do |dir|
      vars = {
        "HOME" => dir,
        "XDG_CONFIG_HOME" => File.join(dir, "config"),
        "XDG_CACHE_HOME" => File.join(dir, "cache"),
        "XDG_DATA_HOME" => File.join(dir, "data"),
        "XDG_DATA_DIRS" => File.join(dir, "system")
      }
      saved = vars.keys.to_h { |key| [key, ENV[key]] }
      begin
        ENV.update(vars)
        yield dir
      ensure
        ENV.update(saved)
      end
    end
  end

  # what the package puts in /usr/share, here under the sandbox's XDG_DATA_DIRS
  def install_package_extension
    dir = File.join(ENV["XDG_DATA_DIRS"], "gnome-shell", "extensions", Stockbar::UUID)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "metadata.json"), "{}")
  end

  def fresh_install_runner(failing: [], **outputs)
    FakeRunner.new(FRESH_INSTALL.merge(outputs), failing: failing)
  end

  def quote(symbol: "AAPL", price: 110.0, previous_close: 100.0, **rest)
    Stockbar::Quote.new(symbol: symbol, price: price, previous_close: previous_close, currency: "USD",
                        stale: false, **rest)
  end
end

class FakeHTTP
  attr_reader :requests

  def initialize(&handler)
    @handler = handler
    @requests = []
  end

  def get_json(url, params)
    @requests << [url, params]
    result = @handler.call(url, params)
    raise result if result.is_a?(Exception)

    result
  end
end

class FakeTerminal < StringIO
  attr_reader :winsize

  def initialize(rows: 24, cols: 80)
    super()
    @winsize = [rows, cols]
  end

  def tty? = true
end

class FakeRunner
  attr_reader :commands

  def initialize(outputs = {}, failing: [])
    @outputs = outputs
    @failing = failing
    @commands = []
  end

  def run(*command)
    @commands << command
    @failing.none? { |prefix| command.first(prefix.size) == prefix }
  end

  def capture(*command, check: true)
    @commands << command
    @outputs.find { |prefix, _| command.first(prefix.size) == prefix }&.last
  end
end

# a Setup or daemon poke that a test forgot to inject would otherwise switch things on the desktop running the tests
module NoRealCommands
  def run(*command)
    raise "test ran a real command: #{command.join(' ')}"
  end

  def capture(*command, **)
    raise "test ran a real command: #{command.join(' ')}"
  end
end
Stockbar::Runner.prepend(NoRealCommands)

Minitest::Test.include(TestHelpers)

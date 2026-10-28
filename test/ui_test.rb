# frozen_string_literal: true

require "test_helper"
require "stockbar/ui"

# the tty-prompt calls ui.rb makes, against the gems in third_party. runs during the package build too,
# so a release whose ruby doesn't get along with them fails there instead of on users' machines
class UITest < Minitest::Test
  LIST = Stockbar::UI::LIST_OPTIONS
  STOCKS = [{ name: "AAPL", value: "AAPL" }, { name: "MSFT", value: "MSFT" }].freeze

  def setup
    Stockbar::UI.require_gems
  end

  def prompt(keys)
    input = StringIO.new(keys)
    def input.wait_readable(*) = true
    def input.ioctl(*) = 80
    Stockbar::UI.prompt(StringIO.new, input: input)
  end

  def test_gems_come_from_third_party
    loaded = $LOADED_FEATURES.grep(%r{/tty/prompt\.rb\z})
    assert_equal 1, loaded.size
    assert loaded.first.start_with?(Stockbar::UI::THIRD_PARTY), "tty-prompt loaded from #{loaded.first}"
  end

  def test_menus
    action = prompt("\r").select("What would you like to do?", cycle: true, per_page: 10) do |menu|
      menu.choice "Add a stock", :add
      menu.choice "Quit", :quit
    end
    assert_equal :add, action

    results = [{ name: "AAPL", value: "AAPL", disabled: "(already added)" }, { name: "MSFT", value: "MSFT" }]
    assert_equal "MSFT", prompt("\r").select("Pick one:", results, **LIST)
    assert_equal "MSFT", prompt("\r").select("Move AAPL to:", STOCKS, default: 2, **LIST)
    assert_equal %w[MSFT], prompt("\r").multi_select("Show in the top bar:", STOCKS, default: [2], **LIST)
  end

  def test_questions
    assert_equal false, prompt("\r").yes?("Show AAPL in the top bar?") { |q| q.default(false) }
    assert_equal "apple", prompt("  apple \r").ask("Company name or ticker:") { |q| q.modify(:strip) }

    seconds = prompt("45\r").ask("Seconds between updates:", default: "20") do |q|
      q.validate(/\A\d+\z/, "Enter a whole number of seconds")
      q.convert(:int)
    end
    assert_equal 45, seconds
  end

  def test_scroll_setting_saves_and_notifies
    in_sandbox do
      ui = Stockbar::UI.allocate
      ui.instance_variable_set(:@prompt, prompt("11\r5\r"))
      ui.instance_variable_set(:@config, Stockbar::Config.load)
      pokes = 0
      ui.instance_variable_set(:@on_change, -> { pokes += 1 })
      ui.send(:scroll)
      assert_equal 5, Stockbar::Config.load.scroll_speed
      assert_equal 1, pokes
    end
  end

  def test_spinner
    spinner = TTY::Spinner.new("[:spinner] Fetching quotes…", format: :dots, output: StringIO.new, clear: true)
    spinner.auto_spin
    spinner.stop
    assert spinner.done?
  end
end

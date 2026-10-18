# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  def cnbc_http
    FakeHTTP.new do |url, _params|
      url.include?("symlookup") ? fixture("cnbc_search_apple.json") : fixture("cnbc_quotes.json")
    end
  end

  def cli(*argv, input: StringIO.new, http: cnbc_http, runner: fresh_install_runner)
    out = StringIO.new
    err = StringIO.new
    pokes = 0
    setup = Stockbar::Setup.new(out: out, runner: runner)
    status = Stockbar::CLI.new(argv, out: out, err: err, input: input, http: http, setup: setup,
                                     on_change: -> { pokes += 1 }).run
    [status, out.string, err.string, pokes]
  end

  def test_first_change_turns_stockbar_on_once
    in_sandbox do
      install_package_extension
      runner = fresh_install_runner
      status, out = cli("add", "AAPL", runner: runner)

      assert_equal 0, status
      assert_includes runner.commands, START_SERVICE
      assert_match "✓ Extension enabled", out
      assert Stockbar::Config.load.setup_done

      runner = fresh_install_runner
      cli("add", "EUR=", runner: runner)
      refute_includes runner.commands, START_SERVICE
      assert_empty(runner.commands.select { |command| command[0, 2] == %w[gsettings set] })
    end
  end

  def test_relogin_reminder_until_the_shell_has_seen_the_extension
    in_sandbox do
      install_package_extension
      _, out = cli("add", "AAPL", runner: fresh_install_runner(failing: [SHELL_INFO]))
      assert out.end_with?("✓ stockbar.service running\n#{Stockbar::Setup::RELOGIN}\n"), out

      # what turn_on wrote to gsettings
      enabled = { ENABLED_EXTENSIONS => "['#{Stockbar::UUID}']\n", IS_ENABLED => "enabled\n" }
      _, out = cli("add", "EUR=", runner: fresh_install_runner(failing: [SHELL_INFO], **enabled))
      assert out.end_with?("Added EUR= (EUR/USD).\n#{Stockbar::Setup::RELOGIN}\n"), out

      _, out = cli("status", runner: fresh_install_runner(failing: [SHELL_INFO], **enabled))
      assert_includes out, Stockbar::Setup::RELOGIN

      _, out = cli("unpin", "EUR=", runner: fresh_install_runner(**enabled))
      refute_includes out, Stockbar::Setup::RELOGIN
    end
  end

  def test_relogin_reminder_is_red_on_a_terminal
    in_sandbox do
      install_package_extension
      out = FakeTerminal.new
      runner = fresh_install_runner(failing: [SHELL_INFO], ENABLED_EXTENSIONS => "['#{Stockbar::UUID}']\n")
      Stockbar::CLI.new(["status"], out: out, setup: Stockbar::Setup.new(out: out, runner: runner)).run

      assert_includes out.string, "\e[31m#{Stockbar::Setup::RELOGIN}\e[0m"
    end
  end

  def test_an_existing_watchlist_gets_turned_on_too
    in_sandbox do
      Stockbar::Config.new(Stockbar::Paths.config_file, "stocks" => [{ "symbol" => "AAPL" }]).save
      install_package_extension
      runner = fresh_install_runner
      cli("pin", "AAPL", runner: runner)

      assert_includes runner.commands, START_SERVICE
    end
  end

  def test_disable_sticks_until_enable
    in_sandbox do
      install_package_extension
      status, out = cli("disable")
      assert_equal 0, status
      assert_match "stockbar enable", out

      runner = fresh_install_runner
      cli("add", "AAPL", runner: runner)
      refute_includes runner.commands, START_SERVICE

      runner = fresh_install_runner
      assert_equal 0, cli("enable", runner: runner).first
      assert_includes runner.commands, START_SERVICE
    end
  end

  def test_failed_turn_on_only_warns
    in_sandbox do
      install_package_extension
      status, out = cli("add", "AAPL", runner: fresh_install_runner(failing: [START_SERVICE]))

      assert_equal 0, status
      assert_match "Couldn't start stockbar.service", out
    end
  end

  def test_enable_without_the_package
    in_sandbox do
      status, _, err = cli("enable")
      assert_equal 1, status
      assert_match "is the stockbar package installed", err
    end
  end

  def test_status
    in_sandbox do
      install_package_extension
      runner = FakeRunner.new({ %w[systemctl --user is-enabled] => "enabled\n",
                                %w[systemctl --user is-active] => "active\n",
                                %w[gsettings get org.gnome.shell enabled-extensions] => "['#{Stockbar::UUID}']\n" })
      _, out = cli("status", runner: runner)
      assert_match(/Service\s+active, enabled/, out)
      assert_match(/Extension\s+enabled/, out)
    end
  end

  def test_add_ticker_pins_the_first_stock_and_writes_the_cache
    in_sandbox do
      status, out, _, pokes = cli("add", "aapl")

      assert_equal 0, status
      assert_equal "Added AAPL (Apple Inc.), shown in the top bar.\n", out
      assert_equal 1, pokes
      assert_equal "AAPL ▲ 0.43% $343.46", Stockbar::Cache.new.read["items"].first["bar_text"]

      cli("add", "SAP-DE")
      assert_equal [true, false], Stockbar::Config.load.stocks.map(&:pinned)
    end
  end

  def test_add_by_name_without_a_terminal_lists_matches
    in_sandbox do
      status, _, err = cli("add", "apple inc")

      assert_equal 1, status
      assert_match "isn't a ticker", err
      assert_match "APC-FF", err
      assert_empty Stockbar::Config.load.stocks
    end
  end

  def test_add_by_name_with_a_terminal_picks_from_results
    in_sandbox do
      input = StringIO.new("2\n")
      def input.tty? = true
      status, out = cli("add", "apple inc", input: input)

      assert_equal 0, status
      assert_match "Pick 1-10", out
      assert_equal %w[APLE], Stockbar::Config.load.symbols
    end
  end

  def test_remove_pin_unpin
    in_sandbox do
      cli("add", "AAPL")
      cli("add", "EUR=")

      assert_equal 0, cli("pin", "eur=").first
      assert_equal [true, true], Stockbar::Config.load.stocks.map(&:pinned)
      assert_equal 0, cli("unpin", "AAPL").first
      assert_equal [false, true], Stockbar::Config.load.stocks.map(&:pinned)

      status, out = cli("remove", "aapl")
      assert_equal 0, status
      assert_equal "Removed AAPL.\n", out
      assert_equal %w[EUR=], Stockbar::Config.load.symbols

      status, _, err = cli("remove", "AAPL")
      assert_equal 1, status
      assert_match "not in the watchlist", err
    end
  end

  def test_list_and_search
    in_sandbox do
      cli("add", "AAPL")
      _, out = cli("list")
      assert_match(/★\s+AAPL\s+Apple Inc\.\s+\$343\.46\s+▲ \+1\.46 \(\+0\.43%\)/, out)

      _, out = cli("search", "apple")
      assert_match(/APC-FF\s+Apple Inc\.\s+Frankfurt Stock Exchange\s+STOCK/, out)
    end
  end

  def test_search_unavailable_suggests_adding_by_ticker
    in_sandbox do
      status, _, err = cli("search", "apple", http: FakeHTTP.new { Stockbar::HTTPError.new("HTTP 503") })

      assert_equal 1, status
      assert_match "add by ticker", err
    end
  end

  def test_interval
    in_sandbox do
      assert_equal [0, "Quotes refresh every 20 s.\n", "", 0], cli("interval")
      assert_equal [0, "Quotes now refresh every 45 s.\n", "", 1], cli("interval", "45")
      assert_equal 45, Stockbar::Config.load.refresh_interval
      assert_equal "Quotes now refresh every 15 s.\n", cli("interval", "5")[1]

      status, _, err = cli("interval", "soon")
      assert_equal 1, status
      assert_match "usage", err
    end
  end

  def test_help_shows_the_logo_on_a_terminal_only
    _, piped = cli("help")
    assert_equal Stockbar::CLI::HELP, piped

    out = FakeTerminal.new
    Stockbar::CLI.new(["--help"], out: out).run
    assert_includes out.string, Stockbar::Banner::BYLINE
    assert out.string.end_with?(Stockbar::CLI::HELP)
  end

  def test_unknown_command
    status, _, err = cli("frobnicate")
    assert_equal 1, status
    assert_match "unknown command", err
  end
end

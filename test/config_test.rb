# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def build_config(data = {})
    Stockbar::Config.new("/nonexistent", data)
  end

  def test_defaults_without_file
    in_sandbox do
      config = Stockbar::Config.load

      assert_equal [], config.stocks
      assert_equal 20, config.refresh_interval
      assert_equal File.join(ENV["XDG_CONFIG_HOME"], "stockbar", "config.json"), config.path
    end
  end

  def test_round_trip_with_private_permissions
    in_sandbox do
      config = Stockbar::Config.load
      config.add("aapl", name: "Apple Inc.", pinned: true)
      config.add(".SPX")
      config.refresh_interval = 120
      config.save

      assert_equal 0o600, File.stat(config.path).mode & 0o777
      assert_empty Dir.glob("#{config.path}.*"), "temp file left behind"

      loaded = Stockbar::Config.load
      assert_equal %w[AAPL .SPX], loaded.symbols
      assert_equal [true, false], loaded.stocks.map(&:pinned)
      assert_equal "Apple Inc.", loaded.find("aapl").name
      assert_equal 120, loaded.refresh_interval
    end
  end

  def test_add_rejects_duplicates
    config = build_config
    config.add("AAPL")
    assert_raises(Stockbar::Error) { config.add("aapl") }
  end

  def test_remove_and_pin_unknown_symbol
    config = build_config
    assert_raises(Stockbar::Error) { config.remove("AAPL") }
    assert_raises(Stockbar::Error) { config.pin("AAPL", true) }
  end

  def test_pinned_symbols
    config = build_config
    %w[AAPL MSFT NVDA].each { |s| config.add(s, pinned: s == "AAPL") }
    config.pinned_symbols = %w[msft NVDA]

    assert_equal [false, true, true], config.stocks.map(&:pinned)
  end

  def test_move
    config = build_config
    %w[A B C D].each { |s| config.add(s) }

    config.move("D", 0)
    assert_equal %w[D A B C], config.symbols
    config.move("D", 99)
    assert_equal %w[A B C D], config.symbols
    config.move("A", 2)
    assert_equal %w[B C A D], config.symbols
  end

  def test_interval_has_a_floor_and_tolerates_junk
    config = build_config("refresh_interval" => 5)
    assert_equal Stockbar::Config::MIN_INTERVAL, config.refresh_interval

    config.refresh_interval = "abc"
    assert_equal Stockbar::Config::DEFAULT_INTERVAL, config.refresh_interval
  end

  def test_invalid_json
    in_sandbox do
      path = Stockbar::Paths.config_file
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{nope")
      assert_raises(Stockbar::Error) { Stockbar::Config.load }
    end
  end
end

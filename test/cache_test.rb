# frozen_string_literal: true

require "test_helper"

class CacheTest < Minitest::Test
  class StubSource
    def initialize(quotes, errors = {})
      @result = Stockbar::CNBC::Result.new(quotes: quotes, errors: errors)
    end

    def quotes(_symbols)
      @result
    end
  end

  def config_with(*symbols)
    config = Stockbar::Config.load
    symbols.each_with_index { |s, i| config.add(s, name: "#{s} Inc.", pinned: i.zero?) }
    config
  end

  def test_writes_what_the_extension_reads
    in_sandbox do
      config = config_with("AAPL", "MSFT", ".SPX")
      now = Time.at(1_760_720_000)
      source = StubSource.new("AAPL" => quote(price: 231.78, previous_close: 228.97, quote_type: "STOCK"),
                              "MSFT" => quote(symbol: "MSFT", price: 410.10, previous_close: 411.79),
                              ".SPX" => quote(symbol: ".SPX", short_name: "S&P 500", price: 7659.44,
                                              previous_close: 7744.06, quote_type: "INDEX"))
      Stockbar::Updater.new(config, source: source).run(now: now)

      data = JSON.parse(File.read(File.join(ENV["XDG_CACHE_HOME"], "stockbar", "quotes.json")))
      assert_equal now.to_i, data["updated_at_epoch"]
      assert_equal now.strftime("%H:%M"), data["updated_at_text"]
      assert_equal 20, data["refresh_interval"]
      assert_nil data["error"]

      aapl, msft, spx = data["items"]
      assert_equal "AAPL ▲ 1.23% $231.78", aapl["bar_text"]
      assert_equal "▲ +2.81 (+1.23%)", aapl["change_text"]
      assert_equal "$231.78", aapl["price_text"]
      assert_equal "AAPL Inc.", aapl["name"]
      assert_equal "up", aapl["direction"]
      assert_equal true, aapl["pinned"]
      assert_equal false, aapl["stale"]
      assert_equal "down", msft["direction"]
      assert_equal false, msft["pinned"]
      assert_equal "S&P 500", spx["display_symbol"]
      assert_equal "S&P 500 ▼ 1.09% 7,659.44", spx["bar_text"]
    end
  end

  def test_failed_symbol_keeps_last_quote_as_stale
    in_sandbox do
      config = config_with("AAPL", "MSFT")
      fresh = quote(short_name: "AAPL", price: 231.78, previous_close: 228.97, quote_type: "STOCK")
      Stockbar::Updater.new(config, source: StubSource.new("AAPL" => fresh)).run

      report = Stockbar::Updater.new(config, source: StubSource.new({}, "AAPL" => "HTTP 503",
                                                                         "MSFT" => "HTTP 503")).run
      assert_equal fresh.to_h.merge(stale: true), report.entries.first.last.to_h

      data = Stockbar::Cache.new.read
      aapl, msft = data["items"]
      assert_equal true, aapl["stale"]
      assert_equal "AAPL ▲ 1.23% $231.78", aapl["bar_text"]
      assert_equal true, msft["stale"]
      assert_equal "MSFT –", msft["bar_text"]
      assert_equal "none", msft["direction"]
      assert_equal "Couldn't update AAPL, MSFT", data["error"]
    end
  end

  def test_read_tolerates_missing_or_broken_file
    in_sandbox do
      cache = Stockbar::Cache.new
      assert_nil cache.read
      assert_equal({}, cache.last_quotes)

      FileUtils.mkdir_p(File.dirname(cache.path))
      File.write(cache.path, "garbage")
      assert_nil cache.read
    end
  end
end

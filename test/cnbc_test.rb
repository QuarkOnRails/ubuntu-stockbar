# frozen_string_literal: true

require "test_helper"

class CNBCTest < Minitest::Test
  SYMBOLS = %w[AAPL .SPX EUR= SAP-DE BTC.CB= NOPE123XYZ].freeze

  def cnbc(&handler)
    @http = FakeHTTP.new(&handler)
    Stockbar::CNBC.new(http: @http)
  end

  def with_quotes
    cnbc { fixture("cnbc_quotes.json") }
  end

  def test_fetches_the_watchlist_in_one_request
    result = with_quotes.quotes(SYMBOLS)

    assert_equal [SYMBOLS.join("|")], @http.requests.map { |_, params| params[:symbols] }
    assert_equal SYMBOLS - %w[NOPE123XYZ], result.quotes.keys
    assert_equal({ "NOPE123XYZ" => "NOPE123XYZ not found" }, result.errors)
  end

  def test_parses_quote_fields
    aapl = with_quotes.quote("AAPL")

    assert_equal ["Apple Inc.", "AAPL", 343.46, 342.0, "USD", "STOCK", false],
                 aapl.to_h.values_at(:name, :short_name, :price, :previous_close, :currency, :quote_type, :stale)
  end

  def test_reads_formatted_numbers_and_short_names
    spx = with_quotes.quote(".SPX")

    assert_in_delta 7659.44, spx.price
    assert_in_delta 7744.06, spx.previous_close
    assert_equal ["S&P 500", "INDEX"], [spx.short_name, spx.quote_type]
  end

  def test_unknown_or_missing_symbol_is_not_found
    assert_raises(Stockbar::NotFound) { with_quotes.quote("NOPE123XYZ") }
    assert_raises(Stockbar::NotFound) { with_quotes.quote("MISSING") }
  end

  def test_quote_without_price_is_an_error
    response = { "FormattedQuoteResult" => { "FormattedQuote" => [{ "symbol" => "X", "code" => 0 }] } }
    result = cnbc { response }.quotes(%w[X])

    assert_equal({ "X" => "no price from CNBC" }, result.errors)
  end

  def test_http_failure_fails_every_symbol_in_the_batch
    result = cnbc { Stockbar::HTTPError.new("HTTP 503") }.quotes(%w[AAPL SAP-DE])

    assert_empty result.quotes
    assert_equal({ "AAPL" => "HTTP 503", "SAP-DE" => "HTTP 503" }, result.errors)
  end

  def test_large_watchlists_are_split_into_batches
    cnbc { {} }.quotes((1..120).map { |i| "S#{i}" })

    assert_equal [50, 50, 20], @http.requests.map { |_, params| params[:symbols].split("|").size }
  end

  def test_search_skips_the_summary_row
    results = cnbc { fixture("cnbc_search_novo.json") }.search("novo nordisk")

    assert_equal %w[NVO NVOH NOV-FF], results.first(3).map(&:symbol)
    assert_equal ["Novo Nordisk A/S", "NYSE", "STOCK"], results.first.to_h.values_at(:name, :exchange, :type)
    assert_equal "novo nordisk", @http.requests.first[1][:prefix]
  end

  def test_search_puts_well_known_names_first
    funds = [{ "symbolName" => "SP500E-CH" }, { "symbolName" => ".SPX" }]

    assert_equal %w[.SPX SP500E-CH], cnbc { funds }.search("S&P 500").map(&:symbol)
    assert_equal %w[.IXIC .NDX], cnbc { [] }.search("nasdaq").map(&:symbol)
  end

  def test_search_failure_suggests_adding_by_ticker
    error = assert_raises(Stockbar::Error) { cnbc { Stockbar::HTTPError.new("HTTP 503") }.search("apple") }
    assert_match "add by ticker", error.message
  end
end

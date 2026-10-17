# frozen_string_literal: true

require "test_helper"

class FormatterTest < Minitest::Test
  F = Stockbar::Formatter

  def test_bar_text_up_down_flat
    assert_equal "AAPL ▲ 1.23% $231.78", F.bar_text("AAPL", quote(price: 231.78, previous_close: 228.97))
    assert_equal "MSFT ▼ 0.41% $410.10", F.bar_text("MSFT", quote(price: 410.10, previous_close: 411.79))
    assert_equal "KO • 0.00% $60.00", F.bar_text("KO", quote(price: 60.0, previous_close: 60.001))
  end

  def test_bar_text_without_quote
    assert_equal "AAPL –", F.bar_text("AAPL", nil)
  end

  def test_change_text
    assert_equal "▲ +2.81 (+1.23%)", F.change(quote(price: 231.78, previous_close: 228.97))
    assert_equal "▼ −1.69 (−0.41%)", F.change(quote(price: 410.10, previous_close: 411.79))
    assert_equal "• 0.00 (0.00%)", F.change(quote(price: 60.0, previous_close: 60.0))
  end

  def test_direction
    assert_equal "up", F.direction(quote(price: 101, previous_close: 100))
    assert_equal "down", F.direction(quote(price: 99, previous_close: 100))
    assert_equal "flat", F.direction(quote(price: 100.004, previous_close: 100))
    assert_equal "none", F.direction(nil)
  end

  def test_thousands_separators
    assert_equal "$64,210.50", F.price(quote(symbol: "BRK.A", price: 64_210.5, quote_type: "STOCK"))
    assert_equal "1,234,567.89", F.number(1_234_567.891, 2)
    assert_equal "−1,000.00", F.number(-1000, 2)
    assert_equal "0.00", F.number(-0.001, 2)
  end

  def test_currencies
    assert_equal "€123.40", F.money(123.4, "EUR", 2)
    assert_equal "1,234.50 Kč", F.money(1234.5, "CZK", 2)
    assert_equal "512.30p", F.money(512.3, "GBp", 2)
    assert_equal "45.20 CHF", F.money(45.2, "CHF", 2)
    assert_equal "45.20", F.money(45.2, nil, 2)
  end

  def test_indices_and_forex_have_no_currency
    index = quote(symbol: ".SPX", price: 5815.03, previous_close: 5800, quote_type: "INDEX")
    forex = quote(symbol: "EUR=", price: 1.0832, previous_close: 1.0851, quote_type: "CURRENCY")

    assert_equal "S&P 500 ▲ 0.26% 5,815.03", F.bar_text("S&P 500", index)
    assert_equal "EUR/USD ▼ 0.18% 1.0832", F.bar_text("EUR/USD", forex)
  end

  def test_display_symbol_prefers_the_short_name
    assert_equal "S&P 500", F.display_symbol(".SPX", quote(symbol: ".SPX", short_name: "S&P 500"))
    assert_equal ".SPX", F.display_symbol(".SPX", nil)
  end

  def test_small_prices_get_more_decimals
    assert_equal "$0.5123", F.price(quote(price: 0.51234, previous_close: 0.5))
    assert_equal "$0.000012", F.price(quote(price: 0.0000123, previous_close: 0.00001))
    assert_equal "$2.50", F.price(quote(price: 2.5, previous_close: 2))
  end

  def test_truncate
    assert_equal "Apple Inc.", F.truncate("Apple Inc.", 28)
    assert_equal "Taiwan Semiconductor Manufa…", F.truncate("Taiwan Semiconductor Manufacturing Company", 28)
  end

  def test_error_summary
    assert_nil F.error_summary({})
    assert_equal "Couldn't update AAPL", F.error_summary("AAPL" => "x")
    errors = %w[A B C D E].to_h { |s| [s, "x"] }
    assert_equal "Couldn't update A, B, C and 2 more", F.error_summary(errors)
  end

  def test_age
    assert_equal "42 s", F.age(42)
    assert_equal "5 min", F.age(300)
    assert_equal "3 h", F.age(3 * 3600)
    assert_equal "3 days", F.age(3 * 86_400)
  end
end

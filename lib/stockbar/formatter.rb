# frozen_string_literal: true

module Stockbar
  module Formatter
    ARROWS = { "up" => "▲", "down" => "▼", "flat" => "•", "none" => "–" }.freeze
    SIGNS = { "up" => "+", "down" => "−" }.freeze
    # anything smaller prints as 0.00%, so no up/down arrow for it
    FLAT_PERCENT = 0.005
    CURRENCY_PREFIX = {
      "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥", "CNY" => "¥", "INR" => "₹",
      "KRW" => "₩", "CAD" => "C$", "AUD" => "A$", "HKD" => "HK$"
    }.freeze
    # GBp/GBX: london quotes are in pence
    CURRENCY_SUFFIX = { "CZK" => " Kč", "PLN" => " zł", "GBp" => "p", "GBX" => "p" }.freeze
    # index points and exchange rates have no currency of their own
    PLAIN_TYPES = %w[INDEX CURRENCY].freeze

    module_function

    def direction(quote)
      return "none" unless quote

      percent = quote.change_percent
      if percent >= FLAT_PERCENT then "up"
      elsif percent <= -FLAT_PERCENT then "down"
      else "flat"
      end
    end

    def bar_text(label, quote)
      return "#{label} #{ARROWS['none']}" unless quote

      "#{label} #{ARROWS[direction(quote)]} #{percent(quote)} #{price(quote)}"
    end

    def price(quote)
      currency = PLAIN_TYPES.include?(quote.quote_type) ? nil : quote.currency
      money(quote.price, currency, decimals(quote))
    end

    def change(quote)
      dir = direction(quote)
      sign = SIGNS.fetch(dir, "")
      "#{ARROWS[dir]} #{sign}#{number(quote.change.abs, decimals(quote))} (#{sign}#{percent(quote)})"
    end

    def percent(quote)
      format("%.2f%%", quote.change_percent.abs)
    end

    def money(value, currency, decimals)
      amount = number(value, decimals)
      if CURRENCY_PREFIX.key?(currency) then "#{CURRENCY_PREFIX[currency]}#{amount}"
      elsif CURRENCY_SUFFIX.key?(currency) then "#{amount}#{CURRENCY_SUFFIX[currency]}"
      elsif currency.to_s.empty? then amount
      else "#{amount} #{currency}"
      end
    end

    def number(value, decimals)
      digits = format("%.#{decimals}f", value.abs)
      grouped = digits.sub(/\A\d+/) { |whole| whole.reverse.scan(/\d{1,3}/).join(",").reverse }
      # a tiny negative change that rounds to zero shouldn't print as −0.00
      value.negative? && digits.match?(/[1-9]/) ? "−#{grouped}" : grouped
    end

    # sub-cent coins would show as $0.00, forex moves in pips (4th decimal)
    def decimals(quote)
      value = quote.price.abs
      return 6 if value.positive? && value < 0.01
      return 4 if value < 1 || quote.quote_type == "CURRENCY"

      2
    end

    def display_symbol(symbol, quote)
      quote&.short_name || symbol
    end

    def display_name(stock, quote)
      stock.name || quote&.name
    end

    def truncate(text, max)
      text = text.to_s
      text.length > max ? "#{text[0, max - 1].rstrip}…" : text
    end

    def error_summary(errors)
      return nil if errors.empty?

      symbols = errors.keys.first(3).join(", ")
      symbols += " and #{errors.size - 3} more" if errors.size > 3
      "Couldn't update #{symbols}"
    end

    def age(seconds)
      if seconds < 90 then "#{seconds} s"
      elsif seconds < 90 * 60 then "#{(seconds / 60.0).round} min"
      elsif seconds < 48 * 3600 then "#{(seconds / 3600.0).round} h"
      else "#{(seconds / 86_400.0).round} days"
      end
    end
  end
end

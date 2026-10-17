# frozen_string_literal: true

require "json"

module Stockbar
  # read by extension/core.js, keep the keys stable
  class Cache
    NAME_LENGTH = 28
    QUOTE_FIELDS = %w[short_name price previous_close currency quote_type].freeze

    attr_reader :path

    def initialize
      @path = Paths.cache_file
    end

    def read
      data = JSON.parse(File.read(path))
      data.is_a?(Hash) ? data : nil
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def last_quotes
      items = read&.fetch("items", nil)
      return {} unless items.is_a?(Array)

      items.each_with_object({}) do |item, quotes|
        next unless item["price"] && item["previous_close"]

        fields = item.slice(*QUOTE_FIELDS).transform_keys(&:to_sym)
        quotes[item["symbol"]] = Quote.new(symbol: item["symbol"], stale: true, **fields)
      end
    end

    def write(entries, refresh_interval:, errors:, now:)
      AtomicFile.write(path, "#{JSON.pretty_generate(payload(entries, refresh_interval, errors, now))}\n")
    end

    private

    def payload(entries, refresh_interval, errors, now)
      {
        "updated_at_epoch" => now.to_i,
        "updated_at_text" => now.strftime("%H:%M"),
        "refresh_interval" => refresh_interval,
        "error" => Formatter.error_summary(errors),
        "errors" => errors,
        "items" => entries.map { |stock, quote| item(stock, quote) }
      }
    end

    def item(stock, quote)
      label = Formatter.display_symbol(stock.symbol, quote)
      item = {
        "symbol" => stock.symbol,
        "display_symbol" => label,
        "name" => Formatter.truncate(Formatter.display_name(stock, quote) || stock.symbol, NAME_LENGTH),
        "pinned" => stock.pinned,
        "direction" => Formatter.direction(quote),
        "bar_text" => Formatter.bar_text(label, quote),
        "price_text" => quote && Formatter.price(quote),
        "change_text" => quote && Formatter.change(quote),
        "stale" => quote.nil? || quote.stale
      }
      quote ? item.merge(QUOTE_FIELDS.to_h { |field| [field, quote[field]] }) : item
    end
  end
end

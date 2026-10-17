# frozen_string_literal: true

module Stockbar
  Quote = Struct.new(:symbol, :name, :short_name, :price, :previous_close, :currency, :quote_type, :stale,
                     keyword_init: true) do
    def change
      price - previous_close
    end

    def change_percent
      previous_close.zero? ? 0.0 : change.to_f / previous_close * 100
    end
  end

  SearchResult = Struct.new(:symbol, :name, :exchange, :type, keyword_init: true)
end

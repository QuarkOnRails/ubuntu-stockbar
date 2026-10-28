# frozen_string_literal: true

module Stockbar
  module Views
    TINTS = { "up" => :green, "down" => :red }.freeze
    NAME_WIDTH = 40
    WATCHLIST_NAME_WIDTH = 34

    module_function

    def watchlist(entries, errors:, color: true)
      table = Table.new(["", "Symbol", "Name", "Price", "Today"], align: [nil, nil, nil, :right, :right], color: color)
      entries.each do |stock, quote|
        today = quote ? Formatter.change(quote) : "no data"
        today += " (old)" if quote&.stale
        table << [
          [stock.pinned ? "★" : "", :yellow],
          [stock.symbol, :bold],
          Formatter.truncate(Formatter.display_name(stock, quote), WATCHLIST_NAME_WIDTH),
          quote ? Formatter.price(quote) : "–",
          [today, quote&.stale ? :dim : TINTS[Formatter.direction(quote)]]
        ]
      end
      legend = Table.paint("★ = pinned in the static top bar; scrolling shows all stocks", :dim, color)
      [table.render, legend, *error_lines(errors, color: color)].join("\n")
    end

    def search_results(results, color:, numbered: false)
      headers = ["Symbol", "Name", "Exchange", "Type"]
      headers.unshift("#") if numbered
      table = Table.new(headers, align: numbered ? [:right] : [], color: color)
      results.each_with_index do |result, i|
        row = [[result.symbol, :bold], Formatter.truncate(result.name, NAME_WIDTH), result.exchange, result.type]
        row.unshift((i + 1).to_s) if numbered
        table << row
      end
      table.render
    end

    def error_lines(errors, color:)
      errors.map { |symbol, message| Table.paint("⚠ #{symbol}: #{message}", :yellow, color) }
    end
  end
end

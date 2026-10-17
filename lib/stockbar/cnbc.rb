# frozen_string_literal: true

module Stockbar
  # undocumented but keyless, batches symbols and still answers non-browser clients (yahoo's API doesn't)
  class CNBC
    QUOTE_URL = "https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
    SEARCH_URL = "https://symlookup.cnbc.com/symservice/symlookup.do"
    BATCH = 50

    Result = Struct.new(:quotes, :errors, keyword_init: true)

    def initialize(http: HTTP.new)
      @http = http
    end

    def quotes(symbols)
      outcomes = symbols.each_slice(BATCH).flat_map { |batch| lookup(batch) }
      failed, found = outcomes.partition { |_, outcome| outcome.is_a?(Error) }
      Result.new(quotes: found.to_h, errors: failed.to_h { |symbol, error| [symbol, error.message] })
    end

    def quote(symbol)
      outcome = lookup([symbol]).first.last
      raise outcome if outcome.is_a?(Error)

      outcome
    end

    def search(query)
      rows = @http.get_json(SEARCH_URL, { prefix: query, partnerid: 20_064, output: "json" })
      Array(rows).filter_map do |row|
        # the first row is a match count summary, not a result
        next unless row["symbolName"]

        SearchResult.new(symbol: row["symbolName"], name: row["companyName"], exchange: row["exchangeName"],
                         type: row["issueType"])
      end
    rescue HTTPError => e
      raise Error, "name search is unavailable right now (#{e.message}), add by ticker instead, e.g. AAPL or SAP-DE"
    end

    private

    def lookup(symbols)
      data = @http.get_json(QUOTE_URL, { symbols: symbols.join("|"), requestMethod: "itv", noform: 1, partnerId: 2,
                                         output: "json" })
      items = Array(data.dig("FormattedQuoteResult", "FormattedQuote")).to_h { |item| [item["symbol"], item] }
      symbols.map { |symbol| [symbol, parse(symbol, items[symbol])] }
    rescue HTTPError => e
      symbols.map { |symbol| [symbol, e] }
    end

    def parse(symbol, item)
      # unknown symbols still come back in a 200, flagged by a nonzero code
      return NotFound.new("#{symbol} not found") unless item && item["code"] == 0

      price, previous = item.values_at("last", "previous_day_closing").map { |text| number(text) }
      return Error.new("no price from CNBC") unless price && previous

      Quote.new(symbol: symbol, name: item["name"], short_name: item["shortName"], price: price,
                previous_close: previous, currency: item["currencyCode"], quote_type: item["type"], stale: false)
    end

    # cnbc sends formatted numbers like "7,659.44"
    def number(text)
      Float(text.to_s.delete(","), exception: false)
    end
  end
end

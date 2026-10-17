# frozen_string_literal: true

module Stockbar
  # undocumented but keyless, batches symbols and still answers non-browser clients (yahoo's API doesn't)
  class CNBC
    QUOTE_URL = "https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
    SEARCH_URL = "https://symlookup.cnbc.com/symservice/symlookup.do"
    BATCH = 50

    Result = Struct.new(:quotes, :errors, keyword_init: true)

    # the lookup only matches the start of a symbol or a name, so the usual ways of writing these
    # ("sp500", "dow jones", "eurusd", "gold") miss them or find only lookalike funds
    WELL_KNOWN = [
      [".SPX", "S&P 500 Index", "INDEX", %w[sp500 sp snp500 snp spx]],
      [".DJI", "Dow Jones Industrial Average", "INDEX", %w[dow dowjones djia dji]],
      [".IXIC", "NASDAQ Composite", "INDEX", %w[nasdaq nasdaqcomposite ixic]],
      [".NDX", "NASDAQ 100", "INDEX", %w[nasdaq nasdaq100 ndx]],
      [".RUT", "Russell 2000", "INDEX", %w[russell russell2000 rut]],
      [".VIX", "CBOE Volatility Index", "INDEX", %w[vix volatility]],
      [".GDAXI", "DAX", "INDEX", %w[dax dax40 gdaxi]],
      [".FTSE", "FTSE 100", "INDEX", %w[ftse ftse100]],
      [".FCHI", "CAC 40", "INDEX", %w[cac cac40 fchi]],
      [".STOXX50E", "Euro Stoxx 50", "INDEX", %w[eurostoxx eurostoxx50 stoxx50 sx5e]],
      [".N225", "Nikkei 225", "INDEX", %w[nikkei nikkei225 n225]],
      [".HSI", "Hang Seng Index", "INDEX", %w[hangseng hsi]],
      ["EUR=", "EUR/USD", "CURRENCY", %w[eurusd]],
      ["GBP=", "GBP/USD", "CURRENCY", %w[gbpusd]],
      ["JPY=", "USD/JPY", "CURRENCY", %w[usdjpy]],
      ["CHF=", "USD/CHF", "CURRENCY", %w[usdchf]],
      ["BTC.CB=", "Bitcoin/USD Coinbase", "CRYPTO", %w[bitcoin btc btcusd]],
      ["ETH.CB=", "Ethereum/USD Coinbase", "CRYPTO", %w[ethereum ether eth ethusd]],
      ["@GC.1", "Gold futures", "COMMODITY", %w[gold xau xauusd]],
      ["@SI.1", "Silver futures", "COMMODITY", %w[silver xag xagusd]],
      ["@CL.1", "WTI crude oil futures", "COMMODITY", %w[oil crude crudeoil wti]],
      ["@LCO.1", "Brent crude oil futures", "COMMODITY", %w[oil brent brentcrude]],
      ["@NG.1", "Natural gas futures", "COMMODITY", %w[naturalgas natgas]]
    ].map { |symbol, name, type, keys| [SearchResult.new(symbol: symbol, name: name, type: type), keys] }.freeze

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
      found = Array(rows).filter_map do |row|
        # the first row is a match count summary, not a result
        next unless row["symbolName"]

        SearchResult.new(symbol: row["symbolName"], name: row["companyName"], exchange: row["exchangeName"],
                         type: row["issueType"])
      end
      (well_known(query) + found).uniq(&:symbol)
    rescue HTTPError => e
      raise Error, "name search is unavailable right now (#{e.message}), add by ticker instead, e.g. AAPL or SAP-DE"
    end

    private

    # spaces and punctuation don't count, "S&P 500" and "s&p-500" are both sp500
    def well_known(query)
      key = query.downcase.delete("^a-z0-9")
      WELL_KNOWN.filter_map { |result, keys| result if keys.include?(key) }
    end

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

# frozen_string_literal: true

module Stockbar
  class Updater
    Report = Struct.new(:entries, :errors, keyword_init: true)

    def initialize(config, source: CNBC.new)
      @config = config
      @source = source
    end

    def run(now: Time.now)
      cache = Cache.new
      previous = cache.last_quotes
      result = @source.quotes(@config.symbols)
      # a failed symbol keeps its last quote, so the bar doesn't go blank on a network hiccup
      entries = @config.stocks.map { |stock| [stock, result.quotes[stock.symbol] || previous[stock.symbol]] }
      cache.write(entries, refresh_interval: @config.refresh_interval, errors: result.errors, now: now)
      Report.new(entries: entries, errors: result.errors)
    end
  end
end

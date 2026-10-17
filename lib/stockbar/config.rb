# frozen_string_literal: true

require "json"

module Stockbar
  class Config
    DEFAULT_INTERVAL = 20
    MIN_INTERVAL = 15

    Stock = Struct.new(:symbol, :name, :pinned, keyword_init: true)

    attr_reader :path, :stocks, :refresh_interval
    # set once stockbar has turned itself on, or the user chose with enable/disable; later choices
    # (stockbar disable, the Extensions app) are then left alone
    attr_accessor :setup_done

    def self.load
      path = Paths.config_file
      new(path, File.exist?(path) ? JSON.parse(File.read(path)) : {})
    rescue JSON::ParserError => e
      raise Error, "#{path} is not valid JSON (#{e.message.lines.first.strip})"
    end

    def self.normalize(symbol)
      symbol.to_s.strip.upcase
    end

    def initialize(path, data = {})
      @path = path
      self.refresh_interval = data.fetch("refresh_interval", DEFAULT_INTERVAL)
      @setup_done = data["setup_done"] == true
      @stocks = Array(data["stocks"]).filter_map do |entry|
        symbol = self.class.normalize(entry["symbol"])
        Stock.new(symbol: symbol, name: entry["name"], pinned: entry["pinned"] == true) unless symbol.empty?
      end
    end

    def refresh_interval=(seconds)
      @refresh_interval = [Integer(seconds), MIN_INTERVAL].max
    rescue ArgumentError, TypeError
      @refresh_interval = DEFAULT_INTERVAL
    end

    def symbols
      stocks.map(&:symbol)
    end

    def find(symbol)
      symbol = self.class.normalize(symbol)
      stocks.find { |stock| stock.symbol == symbol }
    end

    def include?(symbol)
      !find(symbol).nil?
    end

    def add(symbol, name: nil, pinned: false)
      symbol = self.class.normalize(symbol)
      raise Error, "#{symbol} is already in the watchlist" if include?(symbol)

      stocks << Stock.new(symbol: symbol, name: name, pinned: pinned)
    end

    def remove(symbol)
      stocks.delete(fetch(symbol))
    end

    def pin(symbol, pinned)
      fetch(symbol).pinned = pinned
    end

    def pinned_symbols=(symbols)
      wanted = symbols.map { |symbol| self.class.normalize(symbol) }
      stocks.each { |stock| stock.pinned = wanted.include?(stock.symbol) }
    end

    def move(symbol, index)
      stock = fetch(symbol)
      stocks.delete(stock)
      stocks.insert(index.clamp(0, stocks.size), stock)
    end

    def save
      AtomicFile.write(path, "#{JSON.pretty_generate(to_h)}\n", mode: 0o600)
    end

    def to_h
      data = {
        "refresh_interval" => refresh_interval,
        "stocks" => stocks.map { |s| { "symbol" => s.symbol, "name" => s.name, "pinned" => s.pinned } }
      }
      setup_done ? data.merge("setup_done" => true) : data
    end

    private

    def fetch(symbol)
      find(symbol) || raise(Error, "#{self.class.normalize(symbol)} is not in the watchlist")
    end
  end
end

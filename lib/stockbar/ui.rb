# frozen_string_literal: true

module Stockbar
  class UI
    LIST_OPTIONS = { per_page: 15, cycle: true }.freeze
    SYMBOL_WIDTH = 10

    # tty-prompt, tty-spinner and their dependencies, shipped with stockbar: ubuntu 22.04's own
    # ruby-tty-prompt 0.21 wants pastel 0.7 next to pastel 0.8 and breaks on ruby 3
    THIRD_PARTY = File.join(ROOT, "third_party")

    def self.prompt(output, input: $stdin)
      require_gems
      TTY::Prompt.new(input: input, output: output, interrupt: :exit)
    rescue LoadError, StandardError => e
      raise Error, "the interactive editor can't load tty-prompt from #{THIRD_PARTY}\n" \
                   "(#{e.message.lines.first.to_s.strip})"
    end

    # plain $LOAD_PATH, no bundler or gem activation, so whatever gems the system has can't interfere
    def self.require_gems
      Dir[File.join(THIRD_PARTY, "*", "lib")].each { |dir| $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir) }
      require "tty-prompt"
      require "tty-spinner"
    end

    def initialize(out:, source:, on_change:, notice: nil)
      @prompt = self.class.prompt(out)
      @banner = Banner::Live.new(out)
      @out = out
      @source = source
      @on_change = on_change
      @notice = notice
    end

    def run
      @config = Config.load
      @banner.run do
        refresh
        loop do
          draw
          action = main_menu
          break if action == :quit

          begin
            send(action)
          rescue Error => e
            @notice = Table.paint("⚠ #{e.message}", :yellow)
          end
          @config = Config.load
        end
      end
    end

    private

    def draw
      if @banner.pinned?
        @out.print @banner.clear_content
      else
        @out.print "\e[H\e[2J"
        @out.puts "#{Table.paint('Stockbar', :bold)} #{Table.paint('· watchlist for your top bar', :dim)}"
      end
      @out.puts
      if @config.stocks.empty?
        @out.puts "Your watchlist is empty. Choose “Add a stock” to start."
      else
        @out.puts Views.watchlist(@report.entries, errors: @report.errors)
      end
      @out.puts
      @out.puts @notice if @notice
      @notice = nil
    end

    def main_menu
      @prompt.select("What would you like to do?", cycle: true, per_page: 10) do |menu|
        menu.choice "Add a stock", :add
        unless @config.stocks.empty?
          menu.choice "Remove stocks", :remove
          menu.choice "Choose what's in the top bar", :choose_pinned
          menu.choice "Reorder", :reorder
          menu.choice "Refresh now", :refresh
        end
        menu.choice "Refresh interval: #{@config.refresh_interval} s", :interval
        menu.choice "Quit", :quit
      end
    end

    def add
      query = @prompt.ask("Company name or ticker:") { |q| q.modify(:strip) }
      return if query.to_s.empty?

      results = spin("Searching") { @source.search(query) }
      return @notice = "Nothing found for “#{query}”." if results.empty?

      choices = results.map do |result|
        name = Formatter.truncate(result.name, Views::NAME_WIDTH).ljust(Views::NAME_WIDTH)
        # CNBC::WELL_KNOWN results have no exchange
        listing = [result.exchange, result.type].compact.join(" · ")
        choice = { name: "#{result.symbol.ljust(SYMBOL_WIDTH)} #{name} #{listing}", value: result }
        choice[:disabled] = "(already added)" if @config.include?(result.symbol)
        choice
      end
      choices << { name: "← Cancel", value: :cancel }
      picked = @prompt.select("Pick one:", choices, **list_options)
      return if picked == :cancel

      first_pin = @config.stocks.none?(&:pinned)
      pinned = @prompt.yes?("Show #{picked.symbol} in the top bar?") { |q| q.default(first_pin) }
      @config.add(picked.symbol, name: picked.name, pinned: pinned)
      save_and_refresh "Added #{picked.symbol}."
    end

    def remove
      symbols = @prompt.multi_select("Remove which? (space marks, enter confirms)", stock_choices, **list_options)
      return if symbols.empty?

      symbols.each { |symbol| @config.remove(symbol) }
      save_and_refresh "Removed #{symbols.join(', ')}."
    end

    def choose_pinned
      # tty-prompt defaults are 1-based positions
      pinned = @config.stocks.each.with_index(1).filter_map { |stock, position| position if stock.pinned }
      symbols = @prompt.multi_select("Show in the top bar: (space toggles, enter confirms)", stock_choices,
                                     default: pinned, **list_options)
      @config.pinned_symbols = symbols
      save_and_refresh
    end

    def reorder
      symbol = @prompt.select("Move which stock?", stock_choices, **list_options)
      current = @config.symbols.index(symbol)
      positions = @config.symbols.each_with_index.map do |other, i|
        { name: "#{i + 1}. #{other}#{' ← now' if i == current}", value: i }
      end
      # 1-based, same as choose_pinned's defaults
      index = @prompt.select("Move #{symbol} to:", positions, default: current + 1, **list_options)
      @config.move(symbol, index)
      save_and_refresh
    end

    def interval
      @config.refresh_interval = @prompt.ask("Seconds between updates (at least #{Config::MIN_INTERVAL}):",
                                             default: @config.refresh_interval.to_s) do |q|
        q.validate(/\A\d+\z/, "Enter a whole number of seconds")
        q.convert(:int)
      end
      @config.save
      @on_change.call
    end

    def refresh
      @report = spin("Fetching quotes") { Updater.new(@config, source: @source).run }
    end

    def save_and_refresh(message = nil)
      @config.save
      refresh
      @on_change.call
      @notice = message
    end

    # tty-prompt redraws a list by moving the cursor up, which stops at the banner, so the list has to fit
    # under it. 3 rows for the question, which can wrap
    def list_options
      return LIST_OPTIONS unless @banner.pinned?

      LIST_OPTIONS.merge(per_page: [LIST_OPTIONS[:per_page], @banner.content_rows - 3].min)
    end

    def stock_choices
      @config.stocks.map do |stock|
        { name: "#{stock.symbol.ljust(SYMBOL_WIDTH)} #{Formatter.truncate(stock.name, Views::NAME_WIDTH)}",
          value: stock.symbol }
      end
    end

    def spin(message)
      spinner = TTY::Spinner.new("[:spinner] #{message}…", format: :dots, output: @out, clear: true)
      spinner.auto_spin
      yield
    ensure
      spinner&.stop
    end
  end
end

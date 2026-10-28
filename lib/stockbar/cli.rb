# frozen_string_literal: true

module Stockbar
  class CLI
    HELP = <<~TEXT
      stockbar – stock quotes in the GNOME top bar

      Usage:
        stockbar                       interactive watchlist editor
        stockbar list                  watchlist with current prices
        stockbar search QUERY          search by company name or ticker
        stockbar add QUERY [--pin]     add a stock (offers search results if QUERY isn't a ticker)
        stockbar remove SYMBOL...      remove stocks
        stockbar pin SYMBOL...         show stocks in the static top bar
        stockbar unpin SYMBOL...       remove stocks from the static top bar
        stockbar refresh               fetch quotes now
        stockbar interval [SECONDS]    show or set how often quotes refresh (default 20)
        stockbar scroll [SPEED]        scroll the entire watchlist at speed 1–10 (0 = off, default)
        stockbar status                service, extension and data status
        stockbar enable                turn on the top-bar extension and the background service
                                       (your first watchlist change does this by itself)
        stockbar disable               turn both off again (keeps your watchlist)
        stockbar daemon                run the fetch loop in the foreground (used by the service)

      Symbols are CNBC tickers: AAPL, SAP-DE, .SPX, EUR=, BTC.CB= (stockbar search finds them).
    TEXT

    TICKER = /\A[A-Za-z0-9.=-]{1,15}\z/

    def initialize(argv, out: $stdout, err: $stderr, input: $stdin, http: HTTP.new, setup: Setup.new(out: out),
                   on_change: -> { Daemon.request_refresh })
      @argv = argv.dup
      @out = out
      @err = err
      @input = input
      @source = CNBC.new(http: http)
      @setup = setup
      @on_change = on_change
    end

    def run
      command = @argv.shift
      case command
      when nil then interactive
      when "list", "ls" then list
      when "search" then search(@argv)
      when "add" then add(@argv)
      when "remove", "rm" then remove(@argv)
      when "pin" then pin(@argv, true)
      when "unpin" then pin(@argv, false)
      when "refresh" then refresh
      when "interval" then interval(@argv)
      when "scroll" then scroll(@argv)
      when "status" then status
      when "enable" then enable
      when "disable" then disable
      when "daemon" then Daemon.new(out: @out).run
      when "help", "-h", "--help" then help
      when "version", "-v", "--version" then @out.puts VERSION
      else raise Error, "unknown command \"#{command}\" (see: stockbar help)"
      end
      0
    rescue Error => e
      @err.puts "stockbar: #{e.message}"
      1
    rescue Interrupt
      @err.puts
      130
    end

    private

    def interactive
      require_relative "ui"
      notice = first_use(Config.load).join("\n")
      UI.new(out: @out, source: @source, on_change: @on_change, notice: notice.empty? ? nil : notice,
             warning: relogin_reminder).run
    end

    def help
      @out.puts Banner.static(color: color?), "" if @out.tty? && @out.winsize[1] >= Banner::WIDTH
      @out.puts HELP
    end

    def list
      config = Config.load
      return @out.puts("Your watchlist is empty. Add a stock with: stockbar add NAME") if config.stocks.empty?

      report = updater(config).run
      @out.puts Views.watchlist(report.entries, errors: report.errors, color: color?)
    end

    def search(args)
      query = args.join(" ").strip
      raise Error, "usage: stockbar search QUERY" if query.empty?

      results = @source.search(query)
      return @out.puts("Nothing found for \"#{query}\".") if results.empty?

      @out.puts Views.search_results(results, color: color?)
    end

    def add(args)
      pin = !args.delete("--pin").nil?
      query = args.join(" ").strip
      raise Error, "usage: stockbar add SYMBOL|NAME [--pin]" if query.empty?

      config = Config.load
      match = resolve(query)
      return unless match

      # so the bar shows something right after the first add
      pin ||= config.stocks.none?(&:pinned)
      config.add(match.symbol, name: match.name, pinned: pin)
      save_and_refresh(config, "Added #{match.symbol}#{" (#{match.name})" if match.name}" \
                               "#{', shown in the top bar' if pin}.")
    end

    def remove(symbols)
      raise Error, "usage: stockbar remove SYMBOL..." if symbols.empty?

      config = Config.load
      symbols.each { |symbol| config.remove(symbol) }
      save_and_refresh(config, "Removed #{symbol_list(symbols)}.")
    end

    def pin(symbols, pinned)
      raise Error, "usage: stockbar #{pinned ? 'pin' : 'unpin'} SYMBOL..." if symbols.empty?

      config = Config.load
      symbols.each { |symbol| config.pin(symbol, pinned) }
      save_and_refresh(config, "#{symbol_list(symbols)} now #{pinned ? 'pinned' : 'unpinned'} " \
                               "for the static top bar.")
    end

    def refresh
      report = update_and_notify(Config.load)
      @out.puts "Updated #{report.entries.size - report.errors.size} of #{report.entries.size} quotes."
      warn_errors(report.errors)
    end

    def interval(args)
      config = Config.load
      return @out.puts("Quotes refresh every #{config.refresh_interval} s.") if args.empty?

      seconds = Integer(args.first, exception: false)
      raise Error, "usage: stockbar interval [SECONDS]" unless seconds && args.size == 1

      config.refresh_interval = seconds
      config.save
      @on_change.call
      @out.puts "Quotes now refresh every #{config.refresh_interval} s."
      setup_notes(config)
    end

    def scroll(args)
      config = Config.load
      unless args.empty?
        raise Error, "usage: stockbar scroll [SPEED]" unless args.size == 1 && /\A\d+\z/.match?(args.first)

        config.scroll_speed = args.first.to_i
        config.save
        @on_change.call
        setup_notes(config)
      end
      @out.puts "Scroll speed: #{config.scroll_speed} (0 = off, 10 = fastest)."
    end

    def enable
      remember_setup_choice { @setup.enable }
      remind_relogin
    end

    def disable
      config = remember_setup_choice { @setup.disable }
      @out.puts "Your watchlist stays in #{config.path}. Turn it back on with: stockbar enable"
    end

    def status
      config = Config.load
      data = Cache.new.read

      rows = [
        ["Watchlist", "#{config.stocks.size} stocks, #{config.stocks.count(&:pinned)} pinned"],
        ["Service", @setup.service_state],
        ["Extension", @setup.extension_state],
        ["Quotes", data ? "updated #{Formatter.age(Time.now.to_i - data['updated_at_epoch'].to_i)} ago" : "none yet"],
        ["Interval", "every #{config.refresh_interval} s"],
        ["Scroll", "#{config.scroll_speed} (0 = off, 10 = fastest)"],
        ["Config", config.path],
        ["Cache", Paths.cache_file]
      ]
      rows.each { |label, value| @out.puts "#{Table.paint(label.ljust(10), :bold, color?)} #{value}" }
      @setup.warnings.each { |line| @out.puts line }
      remind_relogin
      Views.error_lines(data["errors"], color: color?).each { |line| @out.puts line } if data
    end

    def resolve(query)
      quote = ticker_quote(query)
      return quote if quote

      results = @source.search(query)
      raise Error, "nothing found for \"#{query}\"" if results.empty?

      results.find { |result| result.symbol.casecmp?(query) } || pick(results, query)
    end

    def ticker_quote(query)
      @source.quote(query.upcase) if TICKER.match?(query)
    rescue NotFound
      nil
    end

    def pick(results, query)
      unless @input.tty?
        raise Error, "\"#{query}\" isn't a ticker. Matches:\n#{Views.search_results(results, color: false)}"
      end

      @out.puts Views.search_results(results, color: color?, numbered: true)
      @out.print "Pick 1-#{results.size} (Enter to cancel): "
      answer = @input.gets.to_s.strip
      return if answer.empty?

      index = Integer(answer, exception: false)
      raise Error, "pick a number from 1 to #{results.size}" unless index&.between?(1, results.size)

      results[index - 1]
    end

    def remember_setup_choice
      config = Config.load
      yield
      config.setup_done = true
      config.save
      config
    end

    def save_and_refresh(config, message)
      config.save
      @out.puts message
      warn_errors(update_and_notify(config).errors)
      setup_notes(config)
    end

    def setup_notes(config)
      first_use(config).each { |line| @out.puts line }
      remind_relogin
    end

    # after `apt install` nothing is on yet, so the first watchlist change (or editor start) turns the
    # extension and the service on. saves call it after the daemon poke: a USR1 that beats the new
    # daemon's trap would kill it
    def first_use(config)
      return [] if config.setup_done

      lines = @setup.turn_on
      return [] unless lines

      config.setup_done = true
      config.save
      lines
    end

    # red and on every change until it's done: everyone skips the relogin, and the bar stays empty until then.
    # after first_use, which is what switches the extension on
    def relogin_reminder
      Table.paint(Setup::RELOGIN, :red, color?) if @setup.relogin_needed?
    end

    def remind_relogin
      reminder = relogin_reminder
      @out.puts reminder if reminder
    end

    # fetch here so the bar updates right away, poke the daemon so its next round uses the new watchlist
    def update_and_notify(config)
      report = updater(config).run
      @on_change.call
      report
    end

    def warn_errors(errors)
      Views.error_lines(errors, color: false).each { |line| @err.puts line }
    end

    def symbol_list(symbols)
      symbols.map { |symbol| Config.normalize(symbol) }.join(", ")
    end

    def updater(config)
      Updater.new(config, source: @source)
    end

    def color?
      @out.tty? && ENV["NO_COLOR"].to_s.empty?
    end
  end
end

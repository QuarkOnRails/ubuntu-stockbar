# frozen_string_literal: true

module Stockbar
  class Daemon
    ERROR_RETRY = 60

    def self.request_refresh
      Runner.new.run("systemctl", "--user", "kill", "--signal=USR1", SERVICE)
    end

    def initialize(out:)
      @out = out
      @stopping = false
      @last_errors = {}
    end

    def run
      # journald gets each line as it happens, not a buffered chunk at exit
      @out.sync = true
      # signals write a byte here to cut wait's sleep short, trap handlers can't safely do more
      @wake_reader, @wake_writer = IO.pipe
      # USR1 comes from "Refresh now" in the dropdown and from CLI edits
      trap("USR1") { wake }
      %w[TERM INT].each do |signal|
        trap(signal) do
          @stopping = true
          wake
        end
      end

      log "started (pid #{Process.pid}, config #{Paths.config_file})"
      until @stopping
        delay = round
        wait(delay) unless @stopping
      end
      log "stopped"
    end

    private

    def round
      # reloaded every round so watchlist edits need no restart
      config = Config.load
      log_errors(Updater.new(config).run.errors)
      config.refresh_interval
    rescue StandardError => e
      log "#{e.class}: #{e.message}"
      ERROR_RETRY
    end

    # only log changes, keeps the journal readable
    def log_errors(errors)
      return if errors == @last_errors

      if errors.empty?
        log "all quotes updated again"
      else
        log "couldn't update #{errors.map { |symbol, message| "#{symbol} (#{message})" }.join(', ')}"
      end
      @last_errors = errors
    end

    def wait(seconds)
      return unless IO.select([@wake_reader], nil, nil, seconds)

      @wake_reader.read_nonblock(64, exception: false)
    end

    def wake
      @wake_writer.write_nonblock(".", exception: false)
    end

    def log(message)
      @out.puts(message)
    end
  end
end

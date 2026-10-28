# frozen_string_literal: true

module Stockbar
  # turns the packaged extension and service on or off for the current user: the package installs
  # them system-wide, but may not touch anyone's home or settings
  class Setup
    SCHEMA = "org.gnome.shell"
    # two lines, so it doesn't wrap mid-word in an 80 column terminal
    RELOGIN = "⚠ Log out and back in once so your stocks show up in the top bar.\n" \
              "  GNOME only loads new extensions at login."
    UPDATE_RELOGIN = "⚠ Stockbar’s extension has been updated.\n" \
                     "  Log out and back in to load the new version."
    USER_EXTENSIONS_OFF = "! GNOME has all extensions switched off (disable-user-extensions), " \
                          "turn them on in the Extensions app"

    def initialize(out: $stdout, runner: Runner.new)
      @out = out
      @runner = runner
    end

    # quiet, for the first watchlist edit: nil when the package isn't installed (a source checkout),
    # otherwise lines about what changed
    def turn_on
      switch_on(quiet: true) if extension_installed?
    end

    def enable
      raise Error, "no #{UUID} extension found, is the stockbar package installed?" unless extension_installed?

      switch_on(quiet: false).each { |line| say line }
    end

    def disable
      remove_from_gsettings("enabled-extensions")
      say "✓ Extension disabled"
      systemctl("disable", "--now", SERVICE)
      say "✓ #{SERVICE} stopped"
    end

    def service_state
      enabled = unit_file_state
      if enabled.empty?
        return systemctl("show-environment") ? "not installed" : "unknown, no systemd user session"
      end

      "#{systemctl_output('is-active', SERVICE)}, #{enabled}"
    end

    def extension_state
      return "not installed" unless extension_installed?

      gsettings_list("enabled-extensions")&.include?(UUID) ? "enabled" : "installed, not enabled"
    end

    def warnings
      user_extensions_off? ? [USER_EXTENSIONS_OFF] : []
    end

    def relogin_notice
      return unless gnome_session?

      path = extension_metadata_path
      return unless path && gsettings_list("enabled-extensions")&.include?(UUID)

      info = @runner.capture("gdbus", "call", "--session", "--dest", "org.gnome.Shell",
                             "--object-path", "/org/gnome/Shell",
                             "--method", "org.gnome.Shell.Extensions.GetExtensionInfo", UUID)
      return unless info
      return RELOGIN if info.match?(/\A\(\s*(?:@a\{sv\}\s*)?\{\},\s*\)\s*\z/)
      return unless info.include?("'uuid': <'#{UUID}'>")

      installed = JSON.parse(File.read(path))["stockbar-fingerprint"]
      loaded = info[/'stockbar-fingerprint': <'([0-9a-f]{64})'>/, 1]
      UPDATE_RELOGIN if installed && installed != loaded
    end

    private

    def switch_on(quiet:)
      extension = enable_extension
      announce = extension == :added || !quiet
      lines = []
      if extension == :failed
        lines << "! Couldn't read your GNOME settings, turn Stockbar on in the Extensions app"
      elsif announce
        lines << "✓ Extension enabled"
      end
      lines << start_service if !quiet || unit_file_state == "disabled"
      lines.concat(warnings) if announce
      lines
    end

    def start_service
      if systemctl("enable", "--now", SERVICE)
        "✓ #{SERVICE} running"
      else
        "! Couldn't start #{SERVICE}, see: systemctl --user status #{SERVICE}"
      end
    end

    def extension_installed?
      !extension_metadata_path.nil?
    end

    def extension_metadata_path
      Paths.extension_dirs.map { |dir| File.join(dir, UUID, "metadata.json") }.find { |path| File.exist?(path) }
    end

    # "enabled" or "disabled", empty when the unit doesn't exist or there's no user manager to ask
    def unit_file_state
      systemctl_output("is-enabled", SERVICE)
    end

    # ubuntu sets ubuntu:GNOME. over ssh, on a tty or on another desktop the shell query fails for other reasons
    def gnome_session?
      ENV["XDG_CURRENT_DESKTOP"].to_s.split(":").include?("GNOME")
    end

    def user_extensions_off?
      gsettings_get("disable-user-extensions").to_s.strip == "true"
    end

    # edits gsettings directly: `gnome-extensions enable` refuses extensions the running
    # shell hasn't seen yet, which is every fresh install on wayland
    def enable_extension
      enabled = gsettings_list("enabled-extensions")
      return :failed unless enabled

      remove_from_gsettings("disabled-extensions")
      return :enabled if enabled.include?(UUID)

      gsettings_set("enabled-extensions", enabled + [UUID]) ? :added : :failed
    end

    def systemctl(*args)
      @runner.run("systemctl", "--user", *args)
    end

    def systemctl_output(*args)
      @runner.capture("systemctl", "--user", *args, check: false).to_s.strip
    end

    def gsettings_get(key)
      @runner.capture("gsettings", "get", SCHEMA, key)
    end

    # nil unless gsettings answered with a list, so a failed read never overwrites the user's list
    def gsettings_list(key)
      raw = gsettings_get(key)
      return unless raw&.match?(/\A\s*(@as\s*)?\[/)

      raw.scan(/'([^']*)'/).flatten
    end

    def gsettings_set(key, list)
      @runner.run("gsettings", "set", SCHEMA, key, "[#{list.map { |uuid| "'#{uuid}'" }.join(', ')}]")
    end

    def remove_from_gsettings(key)
      list = gsettings_list(key)
      gsettings_set(key, list - [UUID]) if list&.include?(UUID)
    end

    def say(message)
      @out.puts(message)
    end
  end
end

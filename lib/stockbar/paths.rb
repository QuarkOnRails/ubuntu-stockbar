# frozen_string_literal: true

module Stockbar
  # the extension finds the cache via GLib.get_user_cache_dir(), keep the two in sync
  module Paths
    module_function

    def config_file
      File.join(xdg("XDG_CONFIG_HOME", ".config"), "stockbar", "config.json")
    end

    def cache_file
      File.join(xdg("XDG_CACHE_HOME", ".cache"), "stockbar", "quotes.json")
    end

    # where GNOME Shell looks: the user's own extensions first, then system-wide ones like the package's
    def extension_dirs
      system = ENV["XDG_DATA_DIRS"].to_s.split(File::PATH_SEPARATOR).reject(&:empty?)
      system = %w[/usr/local/share /usr/share] if system.empty?
      [xdg("XDG_DATA_HOME", ".local/share"), *system].map { |dir| File.join(dir, "gnome-shell", "extensions") }
    end

    def xdg(variable, fallback)
      value = ENV[variable].to_s
      value.empty? ? File.join(Dir.home, fallback) : value
    end
  end
end

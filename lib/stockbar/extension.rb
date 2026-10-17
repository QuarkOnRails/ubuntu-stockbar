# frozen_string_literal: true

require "fileutils"
require "json"

module Stockbar
  # build time only (rake extension, from debian/rules): the package ships the result, not extension/
  module Extension
    CORE_MARKER = "//@@CORE@@"
    # ubuntu 22.04, keep in sync with gnome-shell (>= 42) in debian/control
    OLDEST = 42
    # GNOME 45 moved extensions to ES modules, hence legacy.js and modern.js around core.js
    MODERN_FROM = 45
    TESTED_UP_TO = 50
    SOURCE_DIR = File.join(ROOT, "extension")

    module_function

    def variant_for(major)
      major >= MODERN_FROM ? :modern : :legacy
    end

    def shell_versions(variant, major)
      versions = variant == :legacy ? (OLDEST...MODERN_FROM) : (MODERN_FROM..[TESTED_UP_TO, major].max)
      versions.map(&:to_s)
    end

    def build(dir, major:)
      variant = variant_for(major)
      wrapper = File.read(File.join(SOURCE_DIR, "#{variant}.js"))
      core = File.read(File.join(SOURCE_DIR, "core.js"))
      metadata = {
        "uuid" => UUID,
        "name" => "Stockbar",
        "description" => "Stock quotes from the stockbar CLI in the top bar.",
        "url" => URL,
        "shell-version" => shell_versions(variant, major)
      }
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "extension.js"), wrapper.sub(CORE_MARKER) { core })
      File.write(File.join(dir, "metadata.json"), "#{JSON.pretty_generate(metadata)}\n")
      FileUtils.cp(File.join(SOURCE_DIR, "stylesheet.css"), dir)
      variant
    end
  end
end

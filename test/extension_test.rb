# frozen_string_literal: true

require "test_helper"
require "stockbar/extension"

class ExtensionTest < Minitest::Test
  Extension = Stockbar::Extension

  def test_variant_and_shell_versions
    assert_equal :legacy, Extension.variant_for(42)
    assert_equal :legacy, Extension.variant_for(44)
    assert_equal :modern, Extension.variant_for(45)
    assert_equal %w[42 43 44], Extension.shell_versions(:legacy, 42)
    assert_equal %w[45 46 47 48 49 50], Extension.shell_versions(:modern, 46)
    assert_equal %w[45 46 47 48 49 50 51 52], Extension.shell_versions(:modern, 52)
  end

  def test_fingerprint_tracks_only_generated_code_and_styles
    Dir.mktmpdir do |dir|
      fingerprint = lambda do
        Extension.build(dir, major: 42)
        JSON.parse(File.read(File.join(dir, "metadata.json"))).fetch("stockbar-fingerprint")
      end
      original = fingerprint.call
      assert_match(/\A[0-9a-f]{64}\z/, original)
      assert_equal original, fingerprint.call
      read = File.method(:read)
      %w[core.js stylesheet.css].each do |name|
        changed_read = lambda do |path|
          content = read.call(path)
          path == File.join(Extension::SOURCE_DIR, name) ? content + "\n" : content
        end
        File.stub(:read, changed_read) { refute_equal original, fingerprint.call }
      end
      Extension.build(dir, major: 43)
      assert_equal original, JSON.parse(File.read(File.join(dir, "metadata.json")))["stockbar-fingerprint"]
    end
  end

  def test_builds_both_variants
    Dir.mktmpdir do |dir|
      { legacy: 42, modern: 50 }.each do |variant, major|
        out = File.join(dir, variant.to_s)
        assert_equal variant, Extension.build(out, major: major)
        js = File.read(File.join(out, "extension.js"))
        metadata = JSON.parse(File.read(File.join(out, "metadata.json")))

        refute_includes js, Extension::CORE_MARKER
        assert_includes js, "class StockbarIndicator extends PanelMenu.Button"
        assert_includes js, "function fitStocks("
        assert_includes js, "class StockbarScroll"
        assert_equal Stockbar::UUID, metadata["uuid"]
        assert_equal Stockbar::URL, metadata["url"]
        assert_includes metadata["shell-version"], major.to_s
        assert File.exist?(File.join(out, "stylesheet.css"))
      end

      assert_includes File.read(File.join(dir, "legacy", "extension.js")), "function init()"
      assert_includes File.read(File.join(dir, "modern", "extension.js")), "export default class"
    end
  end
end

# frozen_string_literal: true

require "test_helper"

# a release bumps debian/changelog, this catches a VERSION that didn't follow
class VersionTest < Minitest::Test
  def test_matches_debian_changelog
    changelog = File.read(File.join(Stockbar::ROOT, "debian", "changelog"))
    assert_equal Stockbar::VERSION, changelog[/\Astockbar \(([^)]+)\)/, 1]
  end
end

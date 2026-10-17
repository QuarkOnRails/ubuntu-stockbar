# frozen_string_literal: true

require "test_helper"

class SetupTest < Minitest::Test
  Setup = Stockbar::Setup
  UUID = Stockbar::UUID
  SET_ENABLED = %w[gsettings set org.gnome.shell enabled-extensions].freeze

  # a fresh install next to some other extension the user already has on
  def setup_with(failing: [], **outputs)
    @runner = fresh_install_runner(failing: failing, ENABLED_EXTENSIONS => "['ding@rastersoft.com']\n", **outputs)
    @out = StringIO.new
    Setup.new(out: @out, runner: @runner)
  end

  def gsettings_writes
    @runner.commands.select { |command| command[0, 2] == %w[gsettings set] }
  end

  def test_turn_on_enables_the_extension_and_the_service
    in_sandbox do
      install_package_extension
      lines = setup_with.turn_on

      assert_equal [SET_ENABLED + ["['ding@rastersoft.com', '#{UUID}']"]], gsettings_writes
      assert_includes @runner.commands, START_SERVICE
      assert_equal ["✓ Extension enabled", "✓ stockbar.service running"], lines
    end
  end

  def test_turn_on_asks_for_a_relogin_until_the_shell_has_seen_the_extension
    in_sandbox do
      install_package_extension
      lines = setup_with(failing: [["gnome-extensions", "info", UUID]]).turn_on

      assert_equal Setup::RELOGIN, lines.last
    end
  end

  def test_turn_on_leaves_things_that_are_already_on_alone
    in_sandbox do
      install_package_extension
      lines = setup_with(ENABLED_EXTENSIONS => "['#{UUID}']\n", IS_ENABLED => "enabled\n").turn_on

      assert_empty lines
      assert_empty gsettings_writes
      refute_includes @runner.commands, START_SERVICE
    end
  end

  def test_turn_on_without_the_package_does_nothing
    in_sandbox do
      assert_nil setup_with.turn_on
      assert_empty @runner.commands
    end
  end

  def test_unreadable_gsettings_never_overwrites_the_list
    in_sandbox do
      install_package_extension
      lines = setup_with(ENABLED_EXTENSIONS => nil).turn_on

      assert_empty gsettings_writes
      assert_match "Couldn't read your GNOME settings", lines.first
    end
  end

  def test_turn_on_warns_when_gnome_has_extensions_switched_off
    in_sandbox do
      install_package_extension
      setup = setup_with(%w[gsettings get org.gnome.shell disable-user-extensions] => "true\n")

      assert_includes setup.turn_on, Setup::USER_EXTENSIONS_OFF
      assert_equal [Setup::USER_EXTENSIONS_OFF], setup.warnings
    end
  end

  def test_enable_reports_everything_and_needs_the_package
    in_sandbox do
      assert_raises(Stockbar::Error) { setup_with.enable }

      install_package_extension
      setup_with(ENABLED_EXTENSIONS => "['#{UUID}']\n", IS_ENABLED => "enabled\n").enable
      assert_equal "✓ Extension enabled\n✓ stockbar.service running\n", @out.string
      assert_includes @runner.commands, START_SERVICE

      setup_with(failing: [START_SERVICE]).enable
      assert_match "Couldn't start stockbar.service", @out.string
    end
  end

  def test_disable
    in_sandbox do
      setup_with(ENABLED_EXTENSIONS => "['ding@rastersoft.com', '#{UUID}']\n").disable

      assert_equal [SET_ENABLED + ["['ding@rastersoft.com']"]], gsettings_writes
      assert_includes @runner.commands, %w[systemctl --user disable --now stockbar.service]
    end
  end

  def test_states
    in_sandbox do
      assert_equal "not installed", setup_with(IS_ENABLED => "").service_state
      assert_equal "unknown, no systemd user session",
                   setup_with(IS_ENABLED => "", failing: [%w[systemctl --user show-environment]]).service_state
      assert_equal "inactive, disabled",
                   setup_with(%w[systemctl --user is-active] => "inactive\n").service_state

      assert_equal "not installed", setup_with.extension_state
      install_package_extension
      assert_equal "installed, not enabled", setup_with.extension_state
      assert_equal "enabled", setup_with(ENABLED_EXTENSIONS => "['#{UUID}']\n").extension_state
    end
  end
end

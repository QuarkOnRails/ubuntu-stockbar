# frozen_string_literal: true

require "test_helper"

class BannerTest < Minitest::Test
  B = Stockbar::Banner

  def test_help_logo_with_the_byline_under_its_right_edge
    assert_equal ["", *B::LOGO.map { |row| "  #{row}" }, B::BYLINE.rjust(B::WIDTH)], B.static(color: false)
    assert_match "\e[38;5;161m", B.static(color: true).join
  end

  def test_shine_sweeps_the_logo_then_rests
    resting = B.static(color: true)

    assert_match "\e[97m", B.frame(10).join
    assert_equal resting, B.frame(0)
    assert_equal resting, B.frame(B::SHINE_EVERY - 1)
  end

  def test_live_pins_the_banner_while_the_block_runs
    out = FakeTerminal.new
    live = B::Live.new(out)
    live.run do
      assert live.pinned?
      assert_equal 16, live.content_rows
    end

    refute live.pinned?
    assert_includes out.string, "\e[9;24r"
    assert_includes out.string, "\e[9;1H\e[J"
    assert_includes out.string, B::BYLINE
    assert out.string.end_with?("\e7\e[r\e8")
  end

  def test_live_unpins_when_the_block_raises
    out = FakeTerminal.new
    assert_raises(RuntimeError) { B::Live.new(out).run { raise "boom" } }
    assert out.string.end_with?("\e7\e[r\e8")
  end

  def test_live_stays_off_on_small_terminals_and_pipes
    [FakeTerminal.new(rows: 23), FakeTerminal.new(cols: B::WIDTH), StringIO.new].each do |out|
      live = B::Live.new(out)
      live.run { refute live.pinned? }
      refute_includes out.string, "\e[9;"
    end
  end
end

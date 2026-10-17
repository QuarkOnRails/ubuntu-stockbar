# frozen_string_literal: true

require "io/console"

module Stockbar
  # the editor's header, also printed above stockbar help
  module Banner
    LOGO = <<~ART.lines(chomp: true).freeze
      ███████╗████████╗ ██████╗  ██████╗██╗  ██╗██████╗  █████╗ ██████╗
      ██╔════╝╚══██╔══╝██╔═══██╗██╔════╝██║ ██╔╝██╔══██╗██╔══██╗██╔══██╗
      ███████╗   ██║   ██║   ██║██║     █████╔╝ ██████╔╝███████║██████╔╝
      ╚════██║   ██║   ██║   ██║██║     ██╔═██╗ ██╔══██╗██╔══██║██╔══██╗
      ███████║   ██║   ╚██████╔╝╚██████╗██║  ██╗██████╔╝██║  ██║██║  ██║
      ╚══════╝   ╚═╝    ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
    ART
    BYLINE = "by @QuarkOnRails"
    # so the logo doesn't stick to the terminal's corner
    TOP = 1
    LEFT = 2
    WIDTH = LEFT + LOGO.map(&:length).max
    # the byline takes the row under the logo
    HEIGHT = TOP + LOGO.size + 1
    # the box-drawing edges are the letters' shadow
    SHADOW = "╔╗╚╝║═"
    # the shine moves a column per frame, so a sweep takes about 3 s and the logo rests for the other 3
    FPS = 25
    SHINE_EVERY = 6 * FPS
    SHINE_WIDTH = 4

    module_function

    def static(color:)
      render(nil, color)
    end

    def frame(tick)
      render(shine(tick), true)
    end

    def render(band, color)
      rows = LOGO.each_with_index.map do |row, y|
        cells = row.each_char.with_index.map { |char, x| [char, style(char, band&.cover?(x + y))] }
        (" " * LEFT) + paint(cells, color)
      end
      [*Array.new(TOP, ""), *rows, Table.paint(BYLINE.rjust(WIDTH), :dim, color)]
    end

    # x + y stays the same along a / line, so the band leans like a glare
    def shine(tick)
      start = (tick % SHINE_EVERY) - SHINE_WIDTH
      start...(start + SHINE_WIDTH)
    end

    def style(char, lit)
      if char == " " then nil
      elsif lit then :bright
      elsif SHADOW.include?(char) then :dim
      else :green
      end
    end

    # [character, style] cells, grouped into runs so each run gets one escape
    def paint(cells, color)
      cells.slice_when { |a, b| a[1] != b[1] }.map { |run| Table.paint(run.map(&:first).join, run[0][1], color) }.join
    end

    private_class_method :render, :shine, :style, :paint

    # pinned above the editor, a thread keeps it moving while tty-prompt waits for keys
    class Live
      FRAME = 1.0 / FPS
      # 16 rows for the watchlist and the menu, which the default 80x24 terminal still has
      MIN_ROWS = HEIGHT + 16

      def initialize(out)
        @out = out
        @pinned = false
      end

      def pinned?
        @pinned
      end

      def content_rows
        @size[0] - HEIGHT
      end

      def clear_content
        "\e[#{HEIGHT + 1};1H\e[J"
      end

      def run
        return yield unless @out.tty?

        draw(0)
        # the shell left its cursor anywhere, maybe where the banner is now
        @out.print clear_content if pinned?
        @running = true
        thread = Thread.new { animate }
        yield
      ensure
        @running = false
        thread&.join
        unpin
      end

      private

      def animate
        1.step do |tick|
          sleep FRAME
          break unless @running

          draw(tick)
        end
      rescue IOError, SystemCallError
        # the terminal is gone, nothing left to draw on
      end

      # a frame is one write, so it lands between tty-prompt's writes, and \e7/\e8 leave its cursor where it was.
      # ?2026 shows the frame all at once where the terminal supports it
      def draw(tick)
        size = @out.winsize
        output = +""
        output << resize(size) unless size == @size
        output << repaint(tick) if pinned?
        return if output.empty?

        @out.write("\e[?2026h\e7#{output}\e8\e[?2026l")
        @out.flush
      end

      # menus and the watchlist scroll in the region below the banner, so they can't push it off.
      # a column to spare: \e[K right after a line that fills the row would erase its last character
      def resize(size)
        @size = size
        rows, cols = size
        @pinned = rows >= MIN_ROWS && cols > WIDTH
        @painted = []
        @pinned ? "\e[#{HEIGHT + 1};#{rows}r" : "\e[r"
      end

      # resetting the region homes the cursor
      def unpin
        return unless @pinned

        @pinned = false
        @size = nil
        @out.write("\e7\e[r\e8")
        @out.flush
      end

      # overwrite, then clear what's left: erasing first can show a blank row for a moment
      def repaint(tick)
        Banner.frame(tick).each_with_index.filter_map do |line, i|
          next if @painted[i] == line

          @painted[i] = line
          "\e[#{i + 1};1H#{line}\e[K"
        end.join
      end
    end
  end
end

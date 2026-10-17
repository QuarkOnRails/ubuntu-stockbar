# frozen_string_literal: true

module Stockbar
  # hand-rolled so list and search run without gems
  class Table
    STYLES = { bold: 1, dim: 2, red: 31, green: 32, yellow: 33, bright: 97 }.freeze
    # east asian wide characters take two terminal columns
    WIDE = /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]/

    def self.paint(text, style, enabled = true)
      return text if !enabled || style.nil? || text.empty?

      "\e[#{STYLES.fetch(style)}m#{text}\e[0m"
    end

    def self.width(text)
      text.length + text.scan(WIDE).size
    end

    def initialize(headers, align:, color:)
      @headers = headers
      @align = align
      @color = color
      @rows = []
    end

    def <<(row)
      @rows << row.map { |cell| cell.is_a?(Array) ? [cell[0].to_s, cell[1]] : [cell.to_s, nil] }
      self
    end

    def render
      header = @headers.map { |title| [title, :bold] }
      widths = @headers.each_index.map do |i|
        ([header] + @rows).map { |row| self.class.width(row[i][0]) }.max
      end
      rule = self.class.paint(widths.map { |width| "─" * width }.join("  "), :dim, @color)
      [line(header, widths), rule, *@rows.map { |row| line(row, widths) }].join("\n")
    end

    private

    def line(row, widths)
      row.each_with_index.map do |(text, style), i|
        padding = " " * (widths[i] - self.class.width(text))
        cell = self.class.paint(text, style, @color)
        @align[i] == :right ? padding + cell : cell + padding
      end.join("  ").rstrip
    end
  end
end

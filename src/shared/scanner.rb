require_relative 'source_location'

class DabEndOfStreamError < RuntimeError
end

class DabScanner
  attr_reader :position, :nl_is_whitespace, :content, :source_unit

  def initialize(content, nl_is_whitespace = true, source_unit:)
    @nl_is_whitespace = nl_is_whitespace
    @content = content.freeze
    @position = 0
    @length = @content.length
    @source_unit = DabSourceUnit.validate(source_unit)
    build_location_index
  end

  def filename
    source_unit.filename
  end

  def location_at(offset)
    unless offset.is_a?(Integer) && offset >= 0 && offset <= @length
      raise DabSourceLocationError.new('source location offset is outside scanner content')
    end

    @locations[offset]
  end

  def current_location
    location_at(position)
  end

  def source_span(start_offset, end_offset = position)
    DabSourceSpan.new(
      start_location: location_at(start_offset),
      end_location: location_at(end_offset)
    )
  end

  def eof?
    @position == @length
  end

  def merge!(substream)
    @position = substream.position
  end

  def debug(info = '')
    STDERR.printf("[%-32s] pos %5d next: [%s]\n", info, @position, safe_lookup(32)) if $debug
  end

  def safe_lookup(n)
    ret = lookup(n).gsub(/[\n\r\t]/, '.')
    ret += '.' while ret.length < n
    ret
  end

  def lookup(n = 1)
    @content[@position...(@position + n)]
  end

  def current_char(offset = 0)
    @content[@position + offset]
  end

  def advance!(length = 1)
    raise DabEndOfStreamError.new if eof? || (@position + length) > @length

    @position += length
  end

private

  def build_location_index
    line = 1
    column = 0
    @lines = []
    @locations = []

    (0...@length).each do |offset|
      if @content[offset] == "\n"
        line += 1
        column = 0
      end

      @lines << line
      @locations << DabSourceLocation.new(
        source_unit: source_unit,
        offset: offset,
        line: line,
        column: column
      )
      column += 1 unless @content[offset] == "\n"
    end

    @locations << DabSourceLocation.new(
      source_unit: source_unit,
      offset: @length,
      line: line,
      column: column
    )
    @lines.freeze
    @locations.freeze
  end
end

class DabProgramStream
  attr_reader :position

  def initialize(content)
    @content = content.freeze
    @position = 0
    @length = @content.length
  end

  def eof?
    @position == @length
  end

  def merge!(substream)
    @position = substream.position
  end

  def debug(info = '')
    STDERR.printf("[%-32s] pos %5d next: [%s]\n", info, @position, safe_lookup(32))
  end

  def safe_lookup(n)
    ret = lookup(n).gsub(/[\n\r\t]/, '.')
    ret += '.' while ret.length < n
    ret
  end

  def lookup(n = 1)
    @content[@position...(@position + n)]
  end

  def read_keyword(keyword)
    debug("keyword #{keyword} ?")
    skip_whitespace
    return false unless input_match(keyword)
    advance!(keyword.length)
    return false unless current_char_whitespace?
    advance!
    debug("keyword #{keyword} ok")
    true
  end

  def read_identifier
    debug('identifier ?')
    skip_whitespace
    ret = ''
    while current_char_identifier?
      ret += current_char
      advance!
    end
    skip_whitespace
    unless ret.empty?
      debug('identifier ok')
      ret
    end
  end

  def read_operator(operator)
    debug("operator #{operator} ?")
    skip_whitespace
    return false unless input_match(operator)
    advance!(operator.length)
    debug("operator #{operator} ok")
    true
  end

  def read_string
    debug('string ?')
    skip_whitespace
    return false unless input_match('"')
    advance!
    ret = ''
    until input_match('"')
      break unless current_char
      ret += current_char
      advance!
    end
    return false unless input_match('"')
    advance!
    debug('string ok')
    ret
  end

  def input_match(word)
    for i in 0...word.length do
      return false if current_char(i) != word[i]
    end
    true
  end

  def skip_whitespace
    advance! while current_char_whitespace?
  end

  def current_char_whitespace?
    current_char == ' ' || current_char == "\t" || current_char == "\r" || current_char == "\n"
  end

  def current_char_identifier?
    current_char =~ /[a-z]/
  end

  def current_char(offset = 0)
    @content[@position + offset]
  end

  def advance!(length = 1)
    @position += length
  end
end

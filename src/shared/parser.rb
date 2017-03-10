class SourceString < String
  attr_accessor :source_file
  attr_accessor :source_line
  attr_accessor :source_cstart
  attr_accessor :source_cend

  def initialize(source, file, line, cstart, cend)
    super(source)
    @source_file = file
    @source_line = line
    @source_cstart = cstart
    @source_cend = cend
  end
end

class DabEndOfStreamError < RuntimeError
end

class DabParser
  attr_reader :position
  attr_reader :nl_is_whitespace
  attr_reader :content

  def initialize(content, nl_is_whitespace = true)
    @nl_is_whitespace = nl_is_whitespace
    @content = content.freeze
    @position = 0
    @length = @content.length

    line = 1
    @lines = (0...content.length).map do |n|
      c = content[n]
      if c == "\n"
        line += 1
      end
      [n, line]
    end.to_h
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
    skip_whitespace
    start_pos = @position
    debug("keyword #{keyword} ?")
    return false unless input_match(keyword)
    advance!(keyword.length)
    return false unless current_char_whitespace_or_symbol?
    debug("keyword #{keyword} ok")
    _return_source(keyword, start_pos)
  end

  def filename
    '<input>'
  end

  def _return_source(string, start_pos)
    SourceString.new(string, filename, @lines[start_pos], start_pos, @position)
  end

  def read_identifier
    skip_whitespace
    start_pos = @position
    debug('identifier ?')
    ret = ''
    return nil unless current_char_identifier_start?
    while current_char_identifier?
      ret += current_char
      advance!
    end
    unless ret.empty?
      debug('identifier ok')
      _return_source(ret, start_pos)
    end
  end

  def read_classvar
    skip_whitespace
    start_pos = @position
    debug('classvar ?')
    ret = ''
    return nil unless current_char == '@'
    return nil unless current_char_identifier_start?(1)
    ret += current_char
    advance!
    while current_char_identifier?
      ret += current_char
      advance!
    end
    unless ret.empty?
      debug('classvar ok')
      _return_source(ret, start_pos)
    end
  end

  def read_operator(operator)
    read_any_operator([operator])
  end

  def read_any_operator(operator)
    skip_whitespace
    operator = [operator] unless operator.is_a? Array
    start_pos = @position
    debug("operator #{operator} ?")
    return false unless op = input_match_any(operator)
    advance!(op.length)
    debug("operator #{operator} - #{op} ok")
    _return_source(op, start_pos)
  end

  def read_newline
    skip_whitespace
    debug('newline ?')
    return false unless input_match("\n")
    ret = current_char
    advance!
    debug('newline ok')
    ret
  end

  def read_string
    skip_whitespace
    debug('string ?')
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
    _parse_string(ret)
  end

  def _parse_string(ret)
    ret.gsub('\\n', "\n")
  end

  def read_number
    skip_whitespace
    start_pos = @position
    debug('number ?')
    return false unless current_char_digit_start?
    ret = ''
    if current_char == '-'
      ret += current_char
      advance!
    end
    while current_char_digit?
      break unless current_char
      ret += current_char
      advance!
    end
    debug('number ok')
    _return_source(ret, start_pos)
  end

  def input_match(word)
    for i in 0...word.length
      return false if current_char(i) != word[i]
    end
    true
  end

  def input_match_any(array)
    array.each do |item|
      return item if input_match(item)
    end
    nil
  end

  def current_char_digit?
    current_char =~ /[0-9]/
  end

  def current_char_digit_start?
    current_char_digit? || current_char == '-'
  end

  def current_comment?
    lookup(2) == '/*'
  end

  def current_ruby_comment?
    lookup == '#'
  end

  def skip_comment!
    advance!(2)
    advance! until lookup(2) == '*/'
    advance!(2)
  end

  def skip_ruby_comment!
    advance!
    advance! until lookup == "\n"
  end

  def read_any_character
    if current_comment?
      skip_comment!
      return ' '
    elsif current_ruby_comment?
      skip_ruby_comment!
      return ' '
    end
    ret = current_char
    advance!
    ret
  end

  def non_comment_content
    ret = ''
    ret += read_any_character until eof?
    ret
  end

  def skip_whitespace
    while true
      if current_char_whitespace?
        advance! while current_char_whitespace?
      elsif current_comment?
        skip_comment!
      elsif current_ruby_comment?
        skip_ruby_comment!
      else
        break
      end
    end
  end

  def current_char_whitespace?
    if nl_is_whitespace
      current_char == ' ' || current_char == "\t" || current_char == "\r" || current_char == "\n"
    else
      current_char == ' ' || current_char == "\t" || current_char == "\r"
    end
  end

  def current_char_whitespace_or_symbol?
    current_char_whitespace? || current_char == '<' || current_char == '>'
  end

  def current_char_identifier_start?(n = 0)
    current_char(n) =~ /[a-zA-Z_]/
  end

  def current_char_identifier?
    current_char_identifier_start? || current_char_digit?
  end

  def current_char(offset = 0)
    @content[@position + offset]
  end

  def advance!(length = 1)
    raise DabEndOfStreamError.new if eof? || (@position + length) > @length
    @position += length
  end
end

class DabProgramStream < DabParser
end

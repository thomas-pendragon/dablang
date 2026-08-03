require_relative 'syntax_profile'
require_relative 'source_unit'
require_relative 'scanner'

class String
  def to_stringy
    self
  end

  def _to_s
    self
  end
end

class Symbol
  def to_stringy
    to_s
  end

  def _to_s
    to_s
  end
end

class SourceString < String
  attr_reader :source_span

  def initialize(source, source_span)
    super(source)
    @source = source
    @source_span = DabSourceSpan.validate(source_span)
  end

  def source_file
    source_span.filename
  end

  def source_line
    source_span.start_location.line
  end

  def source_column
    source_span.start_location.column
  end

  def source_cstart
    source_span.start_offset
  end

  def source_cend
    source_span.end_offset
  end

  def +(other)
    span = source_span
    if other.is_a? SourceString
      start_location = if source_cstart <= other.source_cstart
                         source_span.start_location
                       else
                         other.source_span.start_location
                       end
      end_location = if source_cend >= other.source_cend
                       source_span.end_location
                     else
                       other.source_span.end_location
                     end
      span = DabSourceSpan.new(start_location: start_location, end_location: end_location)
    end
    SourceString.new(super, span)
  end

  def source_inspect
    "#{self} (#{source_file}:#{source_line} [#{source_cstart}..#{source_cend}])"
  end

  def _to_s
    @source
  end
end

class DabParser < DabScanner
  def initialize(content, nl_is_whitespace = true, filename = '<input>', source_unit: nil)
    source_unit ||= DabSourceUnit.new(
      input: filename == '<input>' ? :stdin : filename,
      filename: filename,
      syntax_profile: DabSyntaxProfile::LEGACY
    )
    super(content, nl_is_whitespace, source_unit: source_unit)
  end

  def character_in_line_with_char(char, type)
    line_range_for(char).send(type)
  end

  def annotated_node(source)
    sline = source.source_line
    cstart = source.source_cstart
    cend = source.source_cend
    lstart = character_in_line_with_char(cstart, :min) + 1
    lend = character_in_line_with_char(cend, :max)
    cstart -= lstart
    cend -= lstart
    text = @content[lstart..lend]
    text = text.gsub(/./).each_with_index.map do |char, index|
      if index >= cstart && index < cend
        char = char.colorize(color: :light_white, background: :red)
      end
      char
    end.join

    list = text.lines.each_with_index.map do |line, index|
      sprintf('%4d: ', sline + index).white + line
    end.join("\n")

    "#{list}\n"
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

  def _return_source(string, start_pos)
    SourceString.new(string, source_span(start_pos, @position))
  end

  def read_identifier(options = nil)
    skip_whitespace
    start_pos = @position
    debug('identifier ?')
    ret = ''
    return nil unless current_char_identifier_start?(0, options)

    while current_char_identifier?(options)
      ret += current_char
      advance!
    end
    if current_char_identifier_end?(options)
      ret += current_char
      advance!
    end
    unless ret.empty?
      debug('identifier ok')
      _return_source(ret, start_pos)
    end
  end

  def read_class_identifier
    skip_whitespace
    start_pos = @position
    debug('classid ?')
    ret = ''
    return nil unless current_char_class_start?

    debug('classid !')
    while current_char_identifier?
      ret += current_char
      advance!
    end
    debug('classid ok')
    _return_source(ret, start_pos)
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

  def read_statclassvar
    skip_whitespace
    start_pos = @position
    debug('statclassvar ?')
    ret = ''
    return nil unless lookup(2) == '@@'
    return nil unless current_char_identifier_start?(2)

    ret += current_char
    advance!
    ret += current_char
    advance!
    while current_char_identifier?
      ret += current_char
      advance!
    end
    unless ret.empty?
      debug('statclassvar ok')
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

  def read_string(doubled_quotes = false)
    skip_whitespace
    start_pos = @position
    debug('string ?')
    return false unless input_match('"')

    advance!
    ret = ''
    loop do
      break unless current_char
      break if input_match('"') && (!doubled_quotes || !input_match('""'))

      if doubled_quotes && input_match('""')
        ret += '"'
        advance!(2)
      else
        ret += current_char
        advance!
      end
    end
    return false unless input_match('"')

    advance!
    debug('string ok')
    ret = _parse_string(ret)
    _return_source(ret, start_pos)
  end

  def _parse_string(ret)
    ret.gsub('\\n', "\n").gsub('\\r', "\r")
  end

  def read_binary_number
    skip_whitespace
    start_pos = @position
    debug('binary ?')
    return false unless input_match_any(%w[0b0 0b1])

    advance!
    advance!
    ret = ''
    while input_match_any(%w[0 1])
      ret += current_char
      advance!
    end
    debug('binary ok')
    _return_source(ret, start_pos)
  end

  def read_float
    skip_whitespace
    start_pos = @position
    debug('float ?')
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
    return false unless current_char == '.'

    ret += current_char
    advance!
    return false unless current_char_digit?

    while current_char_digit?
      break unless current_char

      ret += current_char
      advance!
    end
    debug('float ok')
    _return_source(ret, start_pos)
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

  def current_cpp_comment?
    lookup(2) == '//'
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

  def skip_cpp_comment!
    advance!(2)
    advance! until lookup == "\n"
  end

  def test_and_skip_any_comment
    if current_comment?
      skip_comment!
    elsif current_ruby_comment?
      skip_ruby_comment!
    elsif current_cpp_comment?
      skip_cpp_comment!
    else
      return false
    end
    true
  end

  def read_any_character
    if test_and_skip_any_comment
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
      elsif test_and_skip_any_comment
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
    current_char_whitespace? || current_char == '<' || current_char == '>' || current_char == '(' || current_char == ')'
  end

  def current_char_identifier_start?(n = 0, _options = nil)
    current_char(n) =~ /[a-zA-Z_]/
  end

  def current_char_class_start?
    debug("current_char.. '#{current_char}' - matches '#{current_char =~ /[A-Z]/}'")
    current_char =~ /[A-Z]/
  end

  def current_char_identifier?(options = nil)
    current_char_identifier_start? || current_char_digit? || (options == :extended && current_char_identifier_extended?)
  end

  def current_char_identifier_end?(_options = nil)
    current_char == '?'
  end

  def current_char_identifier_extended?
    current_char == '%'
  end
end

class DabProgramStream < DabParser
  SYNTAX_PROFILE_UNSPECIFIED = Object.new.freeze

  attr_reader :syntax_profile

  def initialize(content, nl_is_whitespace = true, filename = '<input>',
                 source_unit: nil, syntax_profile: SYNTAX_PROFILE_UNSPECIFIED)
    if source_unit
      unless syntax_profile.equal?(SYNTAX_PROFILE_UNSPECIFIED)
        raise DabSourceUnitError.new('DabProgramStream accepts source_unit: or syntax_profile:, not both')
      end

      @source_unit = DabSourceUnit.validate(source_unit)
    else
      syntax_profile = DabSyntaxProfile::LEGACY if syntax_profile.equal?(SYNTAX_PROFILE_UNSPECIFIED)
      input = filename == '<input>' ? :stdin : filename
      @source_unit = DabSourceUnit.new(input: input, filename: filename, syntax_profile: syntax_profile)
    end
    @syntax_profile = @source_unit.syntax_profile
    @source_unit.require_parser_support!
    super(content, nl_is_whitespace, @source_unit.filename, source_unit: @source_unit)
  end
end

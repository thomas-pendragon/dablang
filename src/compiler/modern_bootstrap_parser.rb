require_relative '../shared/parser'
require_relative 'modern_string_escapes'

class DabModernBootstrapParseError < DabUnsupportedSyntaxProfileError
  GENERIC_MESSAGE = 'unsupported Dab syntax profile "modern": parser is not implemented'.freeze

  attr_reader :source_location, :source_span

  def initialize(message = GENERIC_MESSAGE, source_span:)
    @source_span = DabSourceSpan.validate(source_span)
    @source_location = @source_span.start_location
    super(message)
  end
end

class DabModernBootstrapToken
  attr_reader :kind, :text, :value, :source_span, :diagnostic_message

  def initialize(kind:, text:, source_span:, value: text, diagnostic_message: nil)
    @kind = kind
    @text = text.freeze
    @value = value.freeze
    @source_span = DabSourceSpan.validate(source_span)
    @diagnostic_message = diagnostic_message&.freeze
    freeze
  end

  def source_location
    source_span.start_location
  end

  def source_string
    SourceString.new(text, source_span)
  end
end

class DabModernBootstrapScanner < DabScanner
  IDENTIFIER_START = ('A'..'Z').to_a.concat(('a'..'z').to_a).push('_').freeze
  IDENTIFIER_CONTINUE = (IDENTIFIER_START + ('0'..'9').to_a).freeze
  STRING_ESCAPES = {
    '"' => '"',
    '\\' => '\\',
    'n' => "\n",
    'r' => "\r",
    't' => "\t",
    'b' => "\b",
    'f' => "\f",
    'v' => "\v",
    'a' => "\a",
    'e' => "\e",
  }.freeze
  FIXED_UNICODE_MESSAGE =
    'invalid Modern Unicode escape: expected exactly 4 hexadecimal digits after "\\u"'.freeze
  BRACED_UNICODE_MESSAGE =
    'invalid Modern Unicode escape: expected exactly one code point written as 1..6 hexadecimal ' \
    'digits inside "\\u{...}"'.freeze

  def initialize(content, nl_is_whitespace = true, source_unit:)
    super(content.b, nl_is_whitespace, source_unit: source_unit)
  end

  def next_token
    start_offset = position
    return token(:eof, '', start_offset) if eof?

    case current_char
    when ' '
      advance!
      token(:space, ' ', start_offset)
    when "\n"
      advance!
      token(:line_feed, "\n", start_offset)
    when "\r"
      length = current_char(1) == "\n" ? 2 : 1
      text = content.byteslice(start_offset, length)
      advance!(length)
      token(:carriage_return, text, start_offset)
    when ';'
      advance!
      token(:semicolon, ';', start_offset)
    when '"'
      string_token(start_offset)
    when '#'
      line_comment_token(start_offset)
    when '/'
      return line_comment_token(start_offset) if current_char(1) == '/'

      advance!
      token(:unsupported, '/', start_offset)
    else
      return identifier_token(start_offset) if IDENTIFIER_START.include?(current_char)
      return integer_token(start_offset) if digit?(current_char)

      text = current_char
      advance!
      token(:unsupported, text, start_offset)
    end
  end

private

  def identifier_token(start_offset)
    text = +''
    while !eof? && IDENTIFIER_CONTINUE.include?(current_char)
      text << current_char
      advance!
    end
    diagnostic_message = invalid_literal_identifier_message(text)
    kind = case text
           when 'def' then :def
           when 'end' then :end
           when 'nil' then :nil
           when 'true' then :boolean_true
           when 'false' then :boolean_false
           else diagnostic_message ? :invalid_literal : :identifier
           end
    token(kind, text, start_offset, diagnostic_message: diagnostic_message)
  end

  def integer_token(start_offset)
    text = +''
    while !eof? && digit?(current_char)
      text << current_char
      advance!
    end
    diagnostic_message = invalid_numeric_suffix_message(text)
    return unsupported_token(position, diagnostic_message: diagnostic_message) if diagnostic_message

    token(:integer, text, start_offset)
  end

  def string_token(start_offset)
    raw = +'"'.b
    value = +''.b
    advance!

    loop do
      if eof?
        return unsupported_token(
          position,
          diagnostic_message: 'unterminated Modern String literal'
        )
      end

      marker_offset = position
      case current_char
      when '"'
        raw << current_char
        advance!
        return token(:string, raw, start_offset, value: value)
      when "\n"
        return unsupported_token(
          marker_offset,
          diagnostic_message: 'invalid Modern String literal: literal LF is not allowed; use "\\n"'
        )
      when "\r"
        return unsupported_token(
          marker_offset,
          diagnostic_message: 'invalid Modern String literal: literal CR is not allowed; use "\\r"'
        )
      when "\0"
        return unsupported_token(
          marker_offset,
          diagnostic_message: 'invalid Modern String literal: NUL is not allowed'
        )
      when '\\'
        raw << current_char
        advance!
        if eof?
          return unsupported_token(
            marker_offset,
            diagnostic_message: 'unterminated Modern String literal escape'
          )
        end

        return line_continuation_token(marker_offset) if %W[\n \r].include?(current_char)

        if current_char == "\0"
          return unsupported_token(
            position,
            diagnostic_message: 'invalid Modern String literal: NUL is not allowed'
          )
        end
        return nul_escape_token(marker_offset) if current_char == '0'

        if current_char == 'x'
          return unsupported_escape_token(
            marker_offset,
            2,
            'invalid Modern String literal: hexadecimal byte escapes are not supported'
          )
        end
        if current_char&.between?('1', '7')
          return unsupported_escape_token(
            marker_offset,
            2,
            'invalid Modern String literal: octal escapes are not supported'
          )
        end
        if current_char == 'u'
          invalid_unicode = unicode_escape_token(raw, value, marker_offset)
          return invalid_unicode if invalid_unicode

          next
        end
        if current_char == '#' && current_char(1) == '{'
          raw << '#{'.b
          value << '#{'.b
          advance!(2)
          next
        end

        escape = current_char
        decoded = STRING_ESCAPES[escape]
        unless decoded
          message = "invalid Modern String literal escape #{string_escape_description(escape)}; " \
                    'escape is not in the Dab 0.0.43 closed set'
          return unsupported_token(marker_offset, 2, diagnostic_message: message)
        end

        raw << escape
        value << decoded
        advance!
      when '#'
        if current_char(1) == '{'
          return unsupported_token(
            marker_offset,
            2,
            diagnostic_message: 'invalid Modern String literal: interpolation marker "#{" is reserved'
          )
        end

        raw << current_char
        value << current_char
        advance!
      else
        length = utf8_sequence_length(marker_offset)
        unless length
          byte = content.getbyte(marker_offset)
          message = sprintf('invalid UTF-8 byte 0x%02X in Modern String literal', byte)
          return unsupported_token(marker_offset, diagnostic_message: message)
        end

        bytes = if content.encoding == Encoding::BINARY
                  content.byteslice(marker_offset, length)
                else
                  content[marker_offset, length].b
                end
        raw << bytes
        value << bytes
        advance!(length)
      end
    end
  end

  def unicode_escape_token(raw, value, marker_offset)
    return braced_unicode_escape_token(raw, value, marker_offset) if current_char(1) == '{'

    digits = content.byteslice(position + 1, 4)
    unless digits&.length == 4 && digits.each_byte.all? { |byte| hexadecimal_byte?(byte) }
      return malformed_unicode_token(marker_offset, position + 1, 4, FIXED_UNICODE_MESSAGE)
    end

    source = content.byteslice(position, 5)
    append_unicode_escape(raw, value, marker_offset, source, digits.to_i(16), source.length)
  end

  def braced_unicode_escape_token(raw, value, marker_offset)
    digit_offset = position + 2
    index = digit_offset
    digit_count = 0
    while index < content.length && hexadecimal_byte?(content.getbyte(index))
      digit_count += 1
      if digit_count > 6
        return unsupported_escape_token(marker_offset, index - marker_offset + 1, BRACED_UNICODE_MESSAGE)
      end

      index += 1
    end

    unless digit_count.between?(1, 6) && content.getbyte(index) == '}'.ord
      end_offset = index < content.length ? index + 1 : index
      return unsupported_escape_token(marker_offset, end_offset - marker_offset, BRACED_UNICODE_MESSAGE)
    end

    digits = content.byteslice(digit_offset, digit_count)
    source = content.byteslice(position, index - position + 1)
    append_unicode_escape(raw, value, marker_offset, source, digits.to_i(16), source.length)
  end

  def malformed_unicode_token(marker_offset, digit_offset, digit_count, message)
    index = digit_offset
    digit_count.times do
      break if index >= content.length
      break unless hexadecimal_byte?(content.getbyte(index))

      index += 1
    end
    index += 1 if index < content.length
    unsupported_escape_token(marker_offset, index - marker_offset, message)
  end

  def append_unicode_escape(raw, value, marker_offset, source, codepoint, length_after_slash)
    if codepoint.zero?
      return unsupported_escape_token(
        marker_offset,
        length_after_slash + 1,
        'invalid Modern String literal: escape decodes to NUL, which is not allowed'
      )
    end
    if codepoint.between?(0xd800, 0xdfff)
      message = sprintf('invalid Modern Unicode escape: U+%04X is not a Unicode scalar value', codepoint)
      return unsupported_escape_token(marker_offset, length_after_slash + 1, message)
    end
    if codepoint > 0x10ffff
      message = sprintf('invalid Modern Unicode escape: U+%X is outside Unicode range', codepoint)
      return unsupported_escape_token(marker_offset, length_after_slash + 1, message)
    end

    raw << source
    value << [codepoint].pack('U').b
    advance!(length_after_slash)
    nil
  end

  def line_continuation_token(marker_offset)
    length = current_char == "\r" && current_char(1) == "\n" ? 3 : 2
    unsupported_escape_token(
      marker_offset,
      length,
      'invalid Modern String literal: backslash line continuation is not allowed'
    )
  end

  def nul_escape_token(marker_offset)
    unsupported_escape_token(
      marker_offset,
      2,
      'invalid Modern String literal: escape decodes to NUL, which is not allowed'
    )
  end

  def unsupported_escape_token(marker_offset, length, message)
    unsupported_token(marker_offset, length, diagnostic_message: message)
  end

  def hexadecimal_byte?(byte)
    byte && (byte.between?('0'.ord, '9'.ord) || byte.between?('A'.ord, 'F'.ord) ||
      byte.between?('a'.ord, 'f'.ord))
  end

  def utf8_sequence_length(offset)
    unless content.encoding == Encoding::BINARY
      character = current_char&.b
      return 1 if character&.force_encoding(Encoding::UTF_8)&.valid_encoding?

      return nil
    end

    first = content.getbyte(offset)
    return 1 if first && first <= 0x7f
    return 2 if first&.between?(0xc2, 0xdf) && continuation_byte?(offset + 1)

    if first == 0xe0
      return 3 if continuation_byte?(offset + 1, 0xa0..0xbf) && continuation_byte?(offset + 2)
    elsif first&.between?(0xe1, 0xec) || first&.between?(0xee, 0xef)
      return 3 if continuation_byte?(offset + 1) && continuation_byte?(offset + 2)
    elsif first == 0xed
      return 3 if continuation_byte?(offset + 1, 0x80..0x9f) && continuation_byte?(offset + 2)
    elsif first == 0xf0
      return 4 if continuation_byte?(offset + 1, 0x90..0xbf) &&
                  continuation_byte?(offset + 2) && continuation_byte?(offset + 3)
    elsif first&.between?(0xf1, 0xf3)
      return 4 if continuation_byte?(offset + 1) && continuation_byte?(offset + 2) &&
                  continuation_byte?(offset + 3)
    elsif first == 0xf4
      return 4 if continuation_byte?(offset + 1, 0x80..0x8f) &&
                  continuation_byte?(offset + 2) && continuation_byte?(offset + 3)
    end

    nil
  end

  def continuation_byte?(offset, range = 0x80..0xbf)
    byte = content.getbyte(offset)
    byte && range.cover?(byte)
  end

  def invalid_literal_identifier_message(text)
    return if %w[nil true false].include?(text)

    lowercase = text.downcase
    return "invalid Modern nil literal #{text.inspect}; use \"nil\"" if %w[nil null].include?(lowercase)
    return "invalid Modern Bool literal #{text.inspect}; use #{lowercase.inspect}" if %w[true false].include?(lowercase)

    nil
  end

  def invalid_numeric_suffix_message(integer_text)
    if current_char == '.' && digit?(current_char(1))
      'invalid Modern numeric literal: decimal fractions are not implemented'
    elsif current_char == '_' && digit?(current_char(1))
      'invalid Modern numeric literal: digit separators are not implemented'
    elsif integer_text == '0' && %w[b B o O x X].include?(current_char) &&
          identifier_continue?(current_char(1))
      'invalid Modern numeric literal: base prefixes are not implemented'
    elsif %w[e E].include?(current_char) && exponent_digits_follow?
      'invalid Modern numeric literal: exponents are not implemented'
    end
  end

  def exponent_digits_follow?
    index = 1
    index += 1 if %w[+ -].include?(current_char(index))
    digit?(current_char(index))
  end

  def identifier_continue?(character)
    IDENTIFIER_CONTINUE.include?(character)
  end

  def string_escape_description(escape)
    byte = escape&.getbyte(0)
    escaped = if byte&.between?(0x20, 0x7e)
                "\\#{escape}"
              else
                sprintf('\\x%02X', byte)
              end
    escaped.inspect
  end

  def digit?(character)
    character && character >= '0' && character <= '9'
  end

  def line_comment_token(start_offset)
    text = +''.b
    while !eof? && current_char != "\n"
      text << current_char
      advance!
    end
    token(:line_comment, text, start_offset)
  end

  def unsupported_token(start_offset, length = 1, diagnostic_message: nil)
    length = 0 if start_offset == content.length
    text = content.byteslice(start_offset, length) || ''.b
    DabModernBootstrapToken.new(
      kind: :unsupported,
      text: text,
      source_span: source_span(start_offset, start_offset + length),
      diagnostic_message: diagnostic_message
    )
  end

  def token(kind, text, start_offset, value: text, diagnostic_message: nil)
    DabModernBootstrapToken.new(
      kind: kind,
      text: text,
      value: value,
      source_span: source_span(start_offset, position),
      diagnostic_message: diagnostic_message
    )
  end
end

class DabModernBootstrapMainDeclaration
  attr_reader :source_unit, :source_span, :body_tokens

  def initialize(def_token:, name_token:, body_tokens:, end_token:, final_separator:)
    @def_token = def_token
    @name_token = name_token
    @body_tokens = body_tokens.freeze
    @end_token = end_token
    @source_unit = def_token.source_span.source_unit
    @source_span = DabSourceSpan.new(
      start_location: def_token.source_span.start_location,
      end_location: final_separator.source_span.end_location
    )
    freeze
  end

  def lower_into(unit)
    unless unit.is_a?(DabNodeUnit)
      raise ArgumentError.new('Modern bootstrap lowering requires a DabNodeUnit')
    end

    body = DabNodeTreeBlock.new
    @body_tokens.each do |body_token|
      body.insert(lower_literal(body_token))
    end
    function = DabNodeFunction.new(@name_token.source_string, body, nil)
    function.add_source_parts(
      @def_token.source_string,
      @name_token.source_string,
      @end_token.source_string
    )
    unit.add_function(function)
    function
  end

private

  def lower_literal(token)
    node = case token.kind
           when :nil then DabNodeLiteralNil.new
           when :boolean_true then DabNodeLiteralBoolean.new(true)
           when :boolean_false then DabNodeLiteralBoolean.new(false)
           when :integer then DabNodeLiteralNumber.new(Integer(token.text, 10))
           when :string then DabNodeLiteralString.new(token.value, modern_source: true)
           else raise ArgumentError.new("unsupported Modern bootstrap literal token #{token.kind.inspect}")
           end
    node.add_source_part(token.source_string)
    node
  end
end

class DabModernBootstrapParser
  SEPARATOR_KINDS = %i[line_feed semicolon line_comment].freeze
  LITERAL_KINDS = %i[nil boolean_true boolean_false integer string].freeze
  EXPECT_SPACE_MESSAGE =
    'invalid Modern main declaration: expected one ASCII space after "def"'.freeze
  EXPECT_MAIN_MESSAGE =
    'invalid Modern main declaration: expected "main" after "def "'.freeze
  EXPECT_MAIN_SEPARATOR_MESSAGE =
    'invalid Modern main declaration: expected a separator (LF, semicolon, or line comment) after "main"'.freeze
  EXPECT_LITERAL_SEPARATOR_MESSAGE =
    'invalid Modern main body: expected a separator (LF, semicolon, or line comment) after literal'.freeze
  EXPECT_END_MESSAGE =
    'unterminated Modern main declaration: expected closing "end" before end of file'.freeze
  EXPECT_END_SEPARATOR_MESSAGE =
    'invalid Modern main declaration: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  UNEXPECTED_END_MESSAGE = 'unexpected Modern "end": no open main declaration'.freeze
  INVALID_CR_SEPARATOR_MESSAGE = 'invalid Modern separator: CR and CRLF are not supported; use LF'.freeze
  # This is the checked-in VM Fixnum representation boundary, not a broader
  # decision about the future Dab Numeric contract.
  MAX_LEGACY_FIXNUM_DECIMAL = '9223372036854775807'.freeze

  def initialize(content, source_unit:)
    @source_unit = DabSourceUnit.validate(source_unit)
    unless @source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
      raise DabSourceUnitError.new('Modern bootstrap parser requires DabSyntaxProfile::MODERN')
    end

    @scanner = DabModernBootstrapScanner.new(content, source_unit: @source_unit)
  end

  def parse
    skip_separators
    return nil if peek_token.kind == :eof

    reject(peek_token, UNEXPECTED_END_MESSAGE) if peek_token.kind == :end

    def_token = expect(:def)
    expect_space_after_def
    name_token = expect_main_name
    expect_main_separator
    body_tokens = parse_body
    end_token = expect(:end)
    final_separator = expect_end_separator
    skip_separators
    reject(peek_token, UNEXPECTED_END_MESSAGE) if peek_token.kind == :end
    expect(:eof)

    DabModernBootstrapMainDeclaration.new(
      def_token: def_token,
      name_token: name_token,
      body_tokens: body_tokens,
      end_token: end_token,
      final_separator: final_separator
    )
  end

private

  def expect(kind)
    token = next_token
    reject(token) unless token.kind == kind
    token
  end

  def expect_space_after_def
    token = next_token
    reject(token, EXPECT_SPACE_MESSAGE) unless token.kind == :space
    token
  end

  def expect_main_name
    token = next_token
    return token if token.kind == :identifier && token.text == 'main'

    if %i[identifier invalid_literal].include?(token.kind)
      reject(token)
    else
      reject(token, EXPECT_MAIN_MESSAGE)
    end
  end

  def next_token
    token_buffer.shift || @scanner.next_token
  end

  def peek_token(distance = 0)
    token_buffer << @scanner.next_token while token_buffer.length <= distance
    token_buffer.fetch(distance)
  end

  def expect_main_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    if token.kind == :space && implemented_shell_token_after_spaces?
      reject(token, EXPECT_MAIN_SEPARATOR_MESSAGE)
    end
    if %i[eof nil boolean_true boolean_false integer string end].include?(token.kind)
      reject(token, EXPECT_MAIN_SEPARATOR_MESSAGE)
    end

    reject(token)
  end

  def expect_literal_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    if token.kind == :space && body_boundary_token_after_spaces?
      reject(token, EXPECT_LITERAL_SEPARATOR_MESSAGE)
    end
    if %i[eof end].include?(token.kind)
      reject(token, EXPECT_LITERAL_SEPARATOR_MESSAGE)
    end

    reject(token)
  end

  def expect_end_separator
    token = next_token
    reject_invalid_separator(token)
    reject(token, EXPECT_END_SEPARATOR_MESSAGE) unless separator?(token)
    token
  end

  def parse_body
    tokens = []
    loop do
      skip_separators
      break if peek_token.kind == :end

      reject(peek_token, EXPECT_END_MESSAGE) if peek_token.kind == :eof

      token = next_token
      unless LITERAL_KINDS.include?(token.kind)
        reject(token, token.diagnostic_message || DabModernBootstrapParseError::GENERIC_MESSAGE)
      end
      if token.kind == :integer && integer_overflow?(token.text)
        reject(
          token,
          'Modern integer literal is outside supported range 0..9223372036854775807'
        )
      end
      tokens << token
      expect_literal_separator
    end
    tokens
  end

  def integer_overflow?(text)
    significant = text.sub(/\A0+/, '')
    significant = '0' if significant.empty?
    significant.length > MAX_LEGACY_FIXNUM_DECIMAL.length ||
      (significant.length == MAX_LEGACY_FIXNUM_DECIMAL.length && significant > MAX_LEGACY_FIXNUM_DECIMAL)
  end

  def skip_separators
    loop do
      reject_invalid_separator(peek_token)
      break unless separator?(peek_token)

      next_token
    end
  end

  def separator?(token)
    SEPARATOR_KINDS.include?(token.kind)
  end

  def token_buffer
    @token_buffer ||= []
  end

  def token_after_spaces
    distance = 0
    distance += 1 while peek_token(distance).kind == :space
    peek_token(distance)
  end

  def implemented_shell_token_after_spaces?
    token = token_after_spaces
    separator?(token) || %i[eof carriage_return nil boolean_true boolean_false integer string end].include?(token.kind)
  end

  def body_boundary_token_after_spaces?
    token = token_after_spaces
    separator?(token) || %i[eof carriage_return end].include?(token.kind)
  end

  def reject_invalid_separator(token)
    reject(token, INVALID_CR_SEPARATOR_MESSAGE) if token.kind == :carriage_return
  end

  def reject(token, message = DabModernBootstrapParseError::GENERIC_MESSAGE)
    raise DabModernBootstrapParseError.new(message, source_span: token.source_span)
  end
end

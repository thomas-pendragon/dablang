require_relative '../shared/parser'

class DabModernBootstrapParseError < DabUnsupportedSyntaxProfileError
  attr_reader :source_location

  def initialize(source_location:)
    @source_location = source_location
    super('unsupported Dab syntax profile "modern": parser is not implemented')
  end
end

class DabModernBootstrapToken
  attr_reader :kind, :text, :value, :source_span

  def initialize(kind:, text:, source_span:, value: text)
    @kind = kind
    @text = text.freeze
    @value = value.freeze
    @source_span = DabSourceSpan.validate(source_span)
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
  STRING_ESCAPES = {'"' => '"', 'n' => "\n", 'r' => "\r"}.freeze

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
    kind = case text
           when 'def' then :def
           when 'end' then :end
           when 'nil' then :nil
           when 'true' then :boolean_true
           when 'false' then :boolean_false
           else :identifier
           end
    token(kind, text, start_offset)
  end

  def integer_token(start_offset)
    text = +''
    while !eof? && digit?(current_char)
      text << current_char
      advance!
    end
    token(:integer, text, start_offset)
  end

  def string_token(start_offset)
    raw = +'"'.b
    value = +''.b
    advance!

    loop do
      return unsupported_token(position) if eof?

      marker_offset = position
      case current_char
      when '"'
        raw << current_char
        advance!
        return token(:string, raw, start_offset, value: value)
      when "\n", "\r", "\0"
        return unsupported_token(marker_offset)
      when '\\'
        raw << current_char
        advance!
        return unsupported_token(marker_offset) if eof?

        escape = current_char
        decoded = STRING_ESCAPES[escape]
        return unsupported_token(marker_offset, 2) unless decoded

        raw << escape
        value << decoded
        advance!
      when '#'
        return unsupported_token(marker_offset, 2) if current_char(1) == '{'

        raw << current_char
        value << current_char
        advance!
      else
        length = utf8_sequence_length(marker_offset)
        return unsupported_token(marker_offset) unless length

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

  def unsupported_token(start_offset, length = 1)
    length = 0 if start_offset == content.length
    text = content.byteslice(start_offset, length) || ''.b
    DabModernBootstrapToken.new(
      kind: :unsupported,
      text: text,
      source_span: source_span(start_offset, start_offset + length)
    )
  end

  def token(kind, text, start_offset, value: text)
    DabModernBootstrapToken.new(
      kind: kind,
      text: text,
      value: value,
      source_span: source_span(start_offset, position)
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
           when :string then DabNodeLiteralString.new(token.value)
           else raise ArgumentError.new("unsupported Modern bootstrap literal token #{token.kind.inspect}")
           end
    node.add_source_part(token.source_string)
    node
  end
end

class DabModernBootstrapParser
  SEPARATOR_KINDS = %i[line_feed semicolon line_comment].freeze
  LITERAL_KINDS = %i[nil boolean_true boolean_false integer string].freeze
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

    def_token = expect(:def)
    expect(:space)
    name_token = expect(:identifier)
    reject(name_token) unless name_token.text == 'main'
    expect_separator
    body_tokens = parse_body
    end_token = expect(:end)
    final_separator = expect_separator
    skip_separators
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

  def next_token
    token = @peek_token
    @peek_token = nil
    token || @scanner.next_token
  end

  def peek_token
    @peek_token ||= @scanner.next_token
  end

  def expect_separator
    token = next_token
    reject(token) unless separator?(token)
    token
  end

  def parse_body
    tokens = []
    loop do
      skip_separators
      break if peek_token.kind == :end

      token = next_token
      reject(token) unless LITERAL_KINDS.include?(token.kind)
      reject(token) if token.kind == :integer && integer_overflow?(token.text)
      tokens << token
      expect_separator
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
    next_token while separator?(peek_token)
  end

  def separator?(token)
    SEPARATOR_KINDS.include?(token.kind)
  end

  def reject(token)
    raise DabModernBootstrapParseError.new(source_location: token.source_location)
  end
end

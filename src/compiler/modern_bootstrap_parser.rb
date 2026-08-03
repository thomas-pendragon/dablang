require_relative '../shared/parser'

class DabModernBootstrapParseError < DabUnsupportedSyntaxProfileError
  attr_reader :source_location

  def initialize(source_location:)
    @source_location = source_location
    super('unsupported Dab syntax profile "modern": parser is not implemented')
  end
end

class DabModernBootstrapToken
  attr_reader :kind, :text, :source_span

  def initialize(kind:, text:, source_span:)
    @kind = kind
    @text = text.freeze
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
    else
      return identifier_token(start_offset) if IDENTIFIER_START.include?(current_char)

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
           else :identifier
           end
    token(kind, text, start_offset)
  end

  def token(kind, text, start_offset)
    DabModernBootstrapToken.new(
      kind: kind,
      text: text,
      source_span: source_span(start_offset, position)
    )
  end
end

class DabModernBootstrapMainDeclaration
  attr_reader :source_unit, :source_span

  def initialize(def_token:, name_token:, end_token:, final_line_feed:)
    @def_token = def_token
    @name_token = name_token
    @end_token = end_token
    @source_unit = def_token.source_span.source_unit
    @source_span = DabSourceSpan.new(
      start_location: def_token.source_span.start_location,
      end_location: final_line_feed.source_span.end_location
    )
    freeze
  end

  def lower_into(unit)
    unless unit.is_a?(DabNodeUnit)
      raise ArgumentError.new('Modern bootstrap lowering requires a DabNodeUnit')
    end

    function = DabNodeFunction.new(@name_token.source_string, DabNodeTreeBlock.new, nil)
    function.add_source_parts(
      @def_token.source_string,
      @name_token.source_string,
      @end_token.source_string
    )
    unit.add_function(function)
    function
  end
end

class DabModernBootstrapParser
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
    skip_separators
    end_token = expect(:end)
    final_line_feed = expect_separator
    skip_separators
    expect(:eof)

    DabModernBootstrapMainDeclaration.new(
      def_token: def_token,
      name_token: name_token,
      end_token: end_token,
      final_line_feed: final_line_feed
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
    expect(:line_feed)
  end

  def skip_separators
    next_token while peek_token.kind == :line_feed
  end

  def reject(token)
    raise DabModernBootstrapParseError.new(source_location: token.source_location)
  end
end

require_relative '../shared/parser'
require_relative 'modern_string_escapes'
require_relative 'parts/types'

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

class DabModernBootstrapRegexLiteralSource
  attr_reader :opening, :body, :closing, :source_tokens, :source_span, :source_unit

  def initialize(opening:, body:, closing:)
    @opening = opening
    @body = body
    @closing = closing
    @source_tokens = [opening, body, closing].freeze
    @source_unit = opening.source_span.source_unit
    unless @source_tokens.all? do |token|
      token.is_a?(DabModernBootstrapToken) && token.source_span.source_unit.equal?(@source_unit)
    end
      raise ArgumentError.new('Modern regular-expression literal source tokens must share one source unit')
    end

    @source_span = DabSourceSpan.new(
      start_location: opening.source_span.start_location,
      end_location: closing.source_span.end_location
    )
    freeze
  end

  def source_span_for_pattern_offset(offset)
    unless offset.is_a?(Integer) && offset.between?(0, body.text.bytesize)
      raise DabSourceLocationError.new('Regex pattern byte offset is outside literal body')
    end

    start = body.source_span.start_location
    DabSourceSpan.point(
      source_unit: source_unit,
      offset: start.offset + offset,
      line: start.line,
      column: start.column + offset
    )
  end
end

class DabModernBootstrapInterpolationSplice
  attr_reader :opener_token, :name_token, :closer_token, :source_tokens, :source_span

  def initialize(opener_token:, name_token:, closer_token:)
    @opener_token = opener_token
    @name_token = name_token
    @closer_token = closer_token
    @source_tokens = [opener_token, name_token, closer_token].freeze
    @source_span = DabSourceSpan.new(
      start_location: opener_token.source_span.start_location,
      end_location: closer_token.source_span.end_location
    )
    freeze
  end

  def name
    name_token.text
  end
end

class DabModernBootstrapInterpolatedString
  attr_reader :opening_quote, :parts, :closing_quote, :source_tokens, :source_span

  def initialize(opening_quote:, parts:, closing_quote:)
    @opening_quote = opening_quote
    @parts = parts.freeze
    @closing_quote = closing_quote
    @source_tokens = [
      opening_quote,
      *parts.flat_map { |part| part.respond_to?(:source_tokens) ? part.source_tokens : [part] },
      closing_quote,
    ].freeze
    @source_span = DabSourceSpan.new(
      start_location: opening_quote.source_span.start_location,
      end_location: closing_quote.source_span.end_location
    )
    freeze
  end

  def splices
    parts.grep(DabModernBootstrapInterpolationSplice)
  end

  def lower(consumed:)
    components = parts.filter_map do |part|
      if part.is_a?(DabModernBootstrapInterpolationSplice)
        DabNodeLocalVar.new(part.name_token.source_string).tap do |node|
          node.add_source_part(part.name_token.source_string)
        end
      elsif !part.value.empty?
        DabNodeLiteralString.new(part.value, modern_source: true).tap do |node|
          node.add_source_part(part.source_string)
        end
      end
    end
    DabNodeModernInterpolatedString.new(
      components,
      source: source_tokens.map(&:text).join,
      consumed: consumed
    ).tap do |node|
      node.add_source_parts(*source_tokens.map(&:source_string))
    end
  end
end

class DabModernCallableName
  attr_reader :base_token, :suffix_token, :source_span

  def initialize(base_token:, suffix_token: nil)
    @base_token = base_token
    @suffix_token = suffix_token
    @source_span = DabSourceSpan.new(
      start_location: base_token.source_span.start_location,
      end_location: (suffix_token || base_token).source_span.end_location
    )
    freeze
  end

  def text
    base_token.text + (suffix_token&.text || '')
  end

  def base_source_span
    base_token.source_span
  end

  def suffix_source_span
    suffix_token&.source_span
  end

  def source_parts
    [base_token.source_string, suffix_token&.source_string].compact.freeze
  end

  def source_string
    SourceString.new(text, source_span)
  end
end

class DabModernCallableNameComposer
  SUFFIXES = {
    question_mark: '?',
    bang: '!',
  }.freeze

  def adjacent_suffix?(base_token, suffix_token)
    valid_base?(base_token) && valid_suffix?(suffix_token) &&
      base_token.source_span.source_unit.equal?(suffix_token.source_span.source_unit) &&
      base_token.source_span.end_offset == suffix_token.source_span.start_offset
  end

  def compose(base_token, suffix_token = nil)
    unless valid_base?(base_token)
      raise ArgumentError.new('Modern callable name base must be an identifier token')
    end
    if suffix_token && !adjacent_suffix?(base_token, suffix_token)
      raise ArgumentError.new('Modern callable name suffix must be one adjacent question_mark or bang token')
    end

    DabModernCallableName.new(base_token: base_token, suffix_token: suffix_token)
  end

private

  def valid_base?(token)
    token.is_a?(DabModernBootstrapToken) && token.kind == :identifier
  end

  def valid_suffix?(token)
    token.is_a?(DabModernBootstrapToken) && SUFFIXES[token.kind] == token.text
  end
end

class DabModernBootstrapTypeName
  attr_reader :token

  def initialize(token)
    unless token.is_a?(DabModernBootstrapToken) && token.kind == :identifier
      raise ArgumentError.new('Modern type name requires an identifier token')
    end

    @token = token
    freeze
  end

  def text
    token.text
  end

  def source_span
    token.source_span
  end

  def lower
    DabNodeType.new(token.source_string).tap do |node|
      node.add_source_part(token.source_string)
    end
  end
end

class DabModernBootstrapParameter
  attr_reader :name_token, :colon_token, :type_name

  def initialize(name_token:, colon_token:, type_name:)
    @name_token = name_token
    @colon_token = colon_token
    @type_name = type_name
    freeze
  end

  def name
    name_token.text
  end

  def source_span
    DabSourceSpan.new(
      start_location: name_token.source_span.start_location,
      end_location: type_name.source_span.end_location
    )
  end

  def lower(index)
    DabNodeArgDefinition.new(index, name_token.source_string, type_name.lower, nil).tap do |node|
      node.add_source_parts(name_token.source_string, colon_token.source_string, type_name.token.source_string)
    end
  end
end

module DabModernBootstrapLiterals
module_function

  FLOW_TYPE_NAMES = {
    nil: 'NilClass',
    boolean_true: 'Boolean',
    boolean_false: 'Boolean',
    integer: 'Fixnum',
    string: 'String',
  }.freeze

  def lower(token, consumed: false)
    if token.kind == :interpolated_string
      return token.value.lower(consumed: consumed)
    end

    node = case token.kind
           when :nil then DabNodeLiteralNil.new
           when :boolean_true then DabNodeLiteralBoolean.new(true)
           when :boolean_false then DabNodeLiteralBoolean.new(false)
           when :integer then DabNodeLiteralNumber.new(Integer(token.text, 10))
           when :string then DabNodeLiteralString.new(token.value, modern_source: true)
           when :regex_literal then lower_regex(token)
           else raise ArgumentError.new("unsupported Modern bootstrap literal token #{token.kind.inspect}")
           end
    node.add_source_part(token.source_string)
    node
  end

  def type(token)
    return flow_type(token) if regex_literal?(token)

    lower(token).my_type
  end

  def flow_type(token)
    return DabType.parse('String') if token.kind == :interpolated_string
    return DabTypeRegex.new if regex_literal?(token)

    DabType.parse(FLOW_TYPE_NAMES.fetch(token.kind))
  end

  def regex_literal?(token)
    token.is_a?(DabModernBootstrapToken) && token.kind == :regex_literal
  end

  def lower_regex(token)
    source = token.value
    pattern = DabNodeLiteralString.new(
      source.body.text,
      modern_source: true,
      force_byte_assembly: true
    ).tap do |node|
      node.add_source_part(source.body.source_string)
    end
    DabNodeInstanceCall.new(DabNodeClass.new('Regex'), 'new', [pattern], nil).tap do |node|
      node.add_source_parts(*source.source_tokens.map(&:source_string))
    end
  end
end

class DabModernBootstrapLocalBinding
  attr_reader :let_token, :name_token, :type_name, :equal_token, :initializer_token, :source_tokens, :source_span

  def initialize(let_token:, name_token:, type_name:, equal_token:, initializer_token:, source_tokens:)
    @let_token = let_token
    @name_token = name_token
    @type_name = type_name
    @equal_token = equal_token
    @initializer_token = initializer_token
    @source_tokens = source_tokens.freeze
    @source_span = DabSourceSpan.new(
      start_location: let_token.source_span.start_location,
      end_location: initializer_token.source_span.end_location
    )
    freeze
  end

  def kind
    :let_binding
  end

  def name
    name_token.text
  end

  def initializer_type
    DabModernBootstrapLiterals.flow_type(initializer_token)
  end

  def annotated?
    !type_name.nil?
  end

  def declared_type
    DabType.parse(type_name.text) if annotated?
  end

  def lower
    value = DabModernBootstrapLiterals.lower(initializer_token, consumed: true)
    DabNodeDefineLocalVar.new(name_token.source_string, value, type_name&.lower).tap do |node|
      node.add_source_parts(*source_tokens.map(&:source_string))
    end
  end
end

class DabModernBootstrapMutableLocalBinding
  attr_reader :var_token, :name_token, :type_name, :equal_token, :initializer_token, :source_tokens, :source_span

  def initialize(var_token:, name_token:, type_name:, equal_token:, initializer_token:, source_tokens:)
    @var_token = var_token
    @name_token = name_token
    @type_name = type_name
    @equal_token = equal_token
    @initializer_token = initializer_token
    @source_tokens = source_tokens.freeze
    @source_span = DabSourceSpan.new(
      start_location: var_token.source_span.start_location,
      end_location: initializer_token.source_span.end_location
    )
    freeze
  end

  def kind
    :var_binding
  end

  def name
    name_token.text
  end

  def initializer_type
    DabModernBootstrapLiterals.flow_type(initializer_token)
  end

  def annotated?
    !type_name.nil?
  end

  def declared_type
    DabType.parse(type_name.text) if annotated?
  end

  def lower
    value = DabModernBootstrapLiterals.lower(initializer_token, consumed: true)
    DabNodeDefineLocalVar.new(name_token.source_string, value, type_name&.lower).tap do |node|
      node.add_source_parts(*source_tokens.map(&:source_string))
    end
  end
end

class DabModernBootstrapLocalReassignment
  attr_reader :name_token, :type_name, :equal_token, :value_token, :source_tokens, :source_span

  def initialize(name_token:, type_name:, equal_token:, value_token:, source_tokens:)
    @name_token = name_token
    @type_name = type_name
    @equal_token = equal_token
    @value_token = value_token
    @source_tokens = source_tokens.freeze
    @source_span = DabSourceSpan.new(
      start_location: name_token.source_span.start_location,
      end_location: value_token.source_span.end_location
    )
    freeze
  end

  def kind
    :var_reassignment
  end

  def name
    name_token.text
  end

  def initializer_type
    return unless value_token.is_a?(DabModernBootstrapToken)

    DabModernBootstrapLiterals.flow_type(value_token)
  end

  def lower
    value = DabModernBootstrapLiterals.lower(value_token, consumed: true)
    DabNodeSetLocalVar.new(name_token.source_string, value, type_name&.lower).tap do |node|
      node.add_source_parts(*source_tokens.map(&:source_string))
    end
  end
end

class DabModernBootstrapWhileGuardValueForm
  attr_reader :source_tokens, :source_span

  def initialize(source_tokens)
    unless source_tokens.is_a?(Array) && !source_tokens.empty?
      raise ArgumentError.new('Modern while guard value form requires source tokens')
    end

    @source_tokens = source_tokens.freeze
    @source_span = DabSourceSpan.new(
      start_location: source_tokens.fetch(0).source_span.start_location,
      end_location: source_tokens.fetch(-1).source_span.end_location
    )
    freeze
  end
end

class DabModernBootstrapLocalReference
  attr_reader :name_token

  def initialize(name_token)
    @name_token = name_token
    freeze
  end

  def kind
    :local_reference
  end

  def name
    name_token.text
  end

  def source_span
    name_token.source_span
  end

  def source_tokens
    [name_token].freeze
  end

  def lower
    DabNodeLocalVar.new(name_token.source_string).tap do |node|
      node.add_source_part(name_token.source_string)
    end
  end
end

class DabModernBootstrapBareReturn
  attr_reader :keyword_token, :source_parts, :source_span

  def initialize(keyword_token)
    unless keyword_token.is_a?(DabModernBootstrapToken) && keyword_token.kind == :return
      raise ArgumentError.new('Modern bare return requires a return token')
    end

    @keyword_token = keyword_token
    @source_parts = [keyword_token.source_string].freeze
    @source_span = keyword_token.source_span
    freeze
  end

  def kind
    :bare_return
  end

  def source_tokens
    [keyword_token].freeze
  end

  def lower
    DabNodeReturn.new(DabNodeLiteralNil.new).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end
end

class DabModernBootstrapBreak
  attr_reader :break_token, :source_tokens, :source_parts, :source_span

  def initialize(break_token)
    unless break_token.is_a?(DabModernBootstrapToken) &&
           break_token.kind == :identifier && break_token.text == 'break'
      raise ArgumentError.new('Modern break requires an exact break identifier token')
    end

    @break_token = break_token
    @source_tokens = [break_token].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = break_token.source_span
    freeze
  end

  def kind
    :break_statement
  end

  def lower
    DabNodeBreak.new.tap do |node|
      node.add_source_parts(*source_parts)
    end
  end
end

class DabModernBootstrapNext
  attr_reader :next_token, :source_tokens, :source_parts, :source_span

  def initialize(next_token)
    unless next_token.is_a?(DabModernBootstrapToken) &&
           next_token.kind == :identifier && next_token.text == 'next'
      raise ArgumentError.new('Modern next requires an exact next identifier token')
    end

    @next_token = next_token
    @source_tokens = [next_token].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = next_token.source_span
    freeze
  end

  def kind
    :next_statement
  end

  def lower
    DabNodeNext.new.tap do |node|
      node.add_source_parts(*source_parts)
    end
  end
end

class DabModernBootstrapValueReturn
  attr_reader :keyword_token, :value, :separator_token, :source_tokens, :source_parts, :source_span

  def initialize(keyword_token:, space_token:, value:, separator_token:)
    unless keyword_token.is_a?(DabModernBootstrapToken) && keyword_token.kind == :return
      raise ArgumentError.new('Modern value return requires a return token')
    end
    unless space_token.is_a?(DabModernBootstrapToken) && space_token.kind == :space && space_token.text == ' '
      raise ArgumentError.new('Modern value return requires exactly one ASCII space after return')
    end
    unless separator_token.nil? ||
           (separator_token.is_a?(DabModernBootstrapToken) &&
            DabModernBootstrapParser::SEPARATOR_KINDS.include?(separator_token.kind))
      raise ArgumentError.new('Modern value return requires a body-item separator token')
    end

    value_tokens = if value.respond_to?(:source_tokens)
                     value.source_tokens
                   elsif value.is_a?(DabModernBootstrapToken)
                     [value]
                   else
                     raise ArgumentError.new('Modern value return requires a supported value')
                   end
    @keyword_token = keyword_token
    @value = value
    @separator_token = separator_token
    @source_tokens = [keyword_token, space_token, *value_tokens].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: keyword_token.source_span.start_location,
      end_location: value.source_span.end_location
    )
    freeze
  end

  def kind
    :value_return
  end

  def lower
    lowered_value = if value.is_a?(DabModernBootstrapLiteralMemberCall)
                      value.lower(consumed: true)
                    elsif value.is_a?(DabModernBootstrapLocalReference) ||
                          value.is_a?(DabModernBootstrapDirectCall)
                      value.lower
                    else
                      DabModernBootstrapLiterals.lower(value, consumed: true)
                    end
    DabNodeReturn.new(lowered_value).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end
end

class DabModernBootstrapPostfixGuard
  attr_reader :guarded_item, :space_token, :keyword_token, :condition_space_token, :condition,
              :condition_separator, :source_tokens, :source_parts, :source_span

  def initialize(
    guarded_item:,
    space_token:,
    keyword_token:,
    condition_space_token:,
    condition:,
    condition_separator:
  )
    unless space_token.is_a?(DabModernBootstrapToken) &&
           space_token.kind == :space && space_token.text == ' '
      raise ArgumentError.new('Modern postfix guard requires exactly one ASCII space before its keyword')
    end
    unless keyword_token.is_a?(DabModernBootstrapToken) &&
           keyword_token.kind == :identifier && %w[if unless].include?(keyword_token.text)
      raise ArgumentError.new('Modern postfix guard requires an if or unless keyword token')
    end
    unless condition_space_token.is_a?(DabModernBootstrapToken) &&
           condition_space_token.kind == :space && condition_space_token.text == ' '
      raise ArgumentError.new('Modern postfix guard requires exactly one ASCII space after its keyword')
    end
    unless condition_separator.is_a?(DabModernBootstrapToken) &&
           DabModernBootstrapParser::SEPARATOR_KINDS.include?(condition_separator.kind)
      raise ArgumentError.new('Modern postfix guard requires a body-item separator token')
    end

    @guarded_item = guarded_item
    @space_token = space_token
    @keyword_token = keyword_token
    @condition_space_token = condition_space_token
    @condition = condition
    @condition_separator = condition_separator
    @source_tokens = [
      *guarded_item_tokens,
      space_token,
      keyword_token,
      condition_space_token,
      condition_token,
      condition_separator,
    ].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: guarded_item.source_span.start_location,
      end_location: condition_separator.source_span.end_location
    )
    freeze
  end

  def kind
    :postfix_guard
  end

  def branch_items
    [guarded_item].freeze
  end

  def branch_item_groups
    [branch_items].freeze
  end

  def lower
    selected = lower_guarded_item
    empty = DabNodeTreeBlock.new
    DabNodeIf.new(
      lower_condition,
      keyword_token.text == 'if' ? selected : empty,
      keyword_token.text == 'if' ? empty : selected
    ).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end

private

  def guarded_item_tokens
    return [guarded_item] if guarded_item.is_a?(DabModernBootstrapToken)
    return guarded_item.source_tokens if guarded_item.respond_to?(:source_tokens)

    raise ArgumentError.new('Modern postfix guard requires a supported guarded item')
  end

  def condition_token
    condition.is_a?(DabModernBootstrapLocalReference) ? condition.name_token : condition
  end

  def lower_condition
    return condition.lower if condition.is_a?(DabModernBootstrapLocalReference)

    DabModernBootstrapLiterals.lower(condition, consumed: true)
  end

  def lower_guarded_item
    DabNodeTreeBlock.new.tap do |block|
      lowered = if guarded_item.is_a?(DabModernBootstrapDirectCall)
                  guarded_item.lower_body_items
                elsif guarded_item.respond_to?(:lower)
                  [guarded_item.lower]
                else
                  [DabModernBootstrapLiterals.lower(guarded_item)]
                end
      lowered.each { |node| block.insert(node) }
    end
  end
end

class DabModernBootstrapWhileStatement
  attr_reader :while_token, :space_token, :condition, :condition_separator,
              :loop_items, :end_token, :final_separator, :source_tokens,
              :source_parts, :source_span

  def initialize(
    while_token:,
    space_token:,
    condition:,
    condition_separator:,
    loop_items:,
    end_token:,
    final_separator:
  )
    @while_token = while_token
    @space_token = space_token
    @condition = condition
    @condition_separator = condition_separator
    @loop_items = loop_items.freeze
    @end_token = end_token
    @final_separator = final_separator
    @source_tokens = [
      while_token,
      space_token,
      condition_token,
      condition_separator,
      end_token,
      final_separator,
    ].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: while_token.source_span.start_location,
      end_location: final_separator.source_span.end_location
    )
    freeze
  end

  def kind
    :while_statement
  end

  def lower
    DabNodeWhile.new(lower_condition, lower_loop_items).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end

private

  def condition_token
    condition.is_a?(DabModernBootstrapLocalReference) ? condition.name_token : condition
  end

  def lower_condition
    return condition.lower if condition.is_a?(DabModernBootstrapLocalReference)

    DabModernBootstrapLiterals.lower(condition, consumed: true)
  end

  def lower_loop_items
    DabNodeTreeBlock.new.tap do |block|
      loop_items.each do |item|
        lowered = if item.is_a?(DabModernBootstrapDirectCall)
                    item.lower_body_items
                  elsif item.respond_to?(:lower)
                    [item.lower]
                  else
                    [DabModernBootstrapLiterals.lower(item)]
                  end
        lowered.each { |node| block.insert(node) }
      end
    end
  end
end

class DabModernBootstrapWhenClause
  attr_reader :when_token, :space_token, :pattern, :patterns, :pattern_tokens,
              :pattern_separator, :body, :source_tokens, :source_parts, :source_span

  def initialize(
    when_token:,
    space_token:,
    patterns:,
    pattern_tokens:,
    pattern_separator:,
    body:,
    end_location:
  )
    @when_token = when_token
    @space_token = space_token
    @patterns = patterns.freeze
    @pattern = @patterns.fetch(0)
    @pattern_tokens = pattern_tokens.freeze
    @pattern_separator = pattern_separator
    @body = body.freeze
    @source_tokens = [when_token, space_token, *pattern_tokens, pattern_separator].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: when_token.source_span.start_location,
      end_location: end_location
    )
    freeze
  end
end

class DabModernBootstrapCaseElseClause
  attr_reader :else_token, :separator, :body, :source_tokens, :source_parts, :source_span

  def initialize(else_token:, separator:, body:, end_location:)
    @else_token = else_token
    @separator = separator
    @body = body.freeze
    @source_tokens = [else_token, separator].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: else_token.source_span.start_location,
      end_location: end_location
    )
    freeze
  end
end

class DabModernBootstrapCaseStatement
  REGEX_MATCH_TARGET = DabTypeRegex::INTERNAL_MATCH_TARGET

  attr_reader :case_token, :space_token, :subject, :subject_separator,
              :when_clauses, :else_clause, :end_token, :final_separator,
              :source_tokens, :source_parts, :source_span

  def initialize(
    case_token:,
    space_token:,
    subject:,
    subject_separator:,
    end_token:,
    final_separator:,
    when_clauses: [],
    else_clause: nil
  )
    @case_token = case_token
    @space_token = space_token
    @subject = subject
    @subject_separator = subject_separator
    @when_clauses = when_clauses.freeze
    @else_clause = else_clause
    @end_token = end_token
    @final_separator = final_separator
    @source_tokens = [
      case_token,
      space_token,
      *subject_tokens,
      subject_separator,
      *when_clauses.flat_map(&:source_tokens),
      *else_clause&.source_tokens,
      end_token,
      final_separator,
    ].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: case_token.source_span.start_location,
      end_location: final_separator.source_span.end_location
    )
    freeze
  end

  def kind
    :case_statement
  end

  def lower
    return lower_zero_clause if when_clauses.empty? && else_clause.nil?
    return lower_else_only if when_clauses.empty?

    DabNodeTreeBlock.new.tap do |block|
      subject_identifier = "$modern_case_subject_#{case_token.source_span.start_offset}"
      block.insert(DabNodeDefineLocalVar.new(subject_identifier, lower_subject(consumed: true)))
      append_clause_tail(block, when_clauses, subject_identifier)
    end
  end

private

  def subject_tokens
    return subject.source_tokens if subject.respond_to?(:source_tokens)

    [subject]
  end

  def lower_subject(consumed: false)
    return subject.lower if subject.is_a?(DabModernBootstrapLocalReference) ||
                            subject.is_a?(DabModernBootstrapDirectCall)

    DabModernBootstrapLiterals.lower(subject, consumed: consumed)
  end

  def lower_zero_clause
    DabNodeTreeBlock.new.tap do |block|
      block.insert(lower_subject)
    end
  end

  def lower_else_only
    DabNodeTreeBlock.new.tap do |block|
      block.insert(lower_subject)
      append_body(block, else_clause.body)
    end
  end

  def append_clause_tail(block, clauses, subject_identifier, index = 0)
    if index >= clauses.length
      append_body(block, else_clause.body) if else_clause
      return
    end

    clause = clauses.fetch(index)
    condition = lower_clause_condition(clause.patterns, subject_identifier)
    selected = lower_clause_body(clause.body)
    rejected = DabNodeTreeBlock.new
    append_clause_tail(rejected, clauses, subject_identifier, index + 1)
    block.insert(DabNodeIf.new(condition, selected, rejected))
  end

  def lower_clause_condition(patterns, subject_identifier)
    comparisons = patterns.map do |pattern|
      arguments = DabNode.new
      arguments.insert(DabNodeLocalVar.new(subject_identifier))
      if DabModernBootstrapLiterals.regex_literal?(pattern)
        next DabNodeInstanceCall.new(
          DabModernBootstrapLiterals.lower(pattern, consumed: true),
          REGEX_MATCH_TARGET,
          arguments,
          nil,
          compiler_verified_target: true
        )
      end

      DabNodeInstanceCall.new(
        DabModernBootstrapLiterals.lower(pattern, consumed: true),
        '==',
        arguments,
        nil,
        compiler_verified_target: true
      )
    end
    comparisons.reverse_each.reduce do |right, left|
      DabNodeOperator.new(left, right, :'||')
    end
  end

  def lower_clause_body(items)
    DabNodeTreeBlock.new.tap do |block|
      append_body(block, items)
    end
  end

  def append_body(block, items)
    items.each do |item|
      lowered = if item.is_a?(DabModernBootstrapDirectCall)
                  item.lower_body_items
                elsif item.respond_to?(:lower)
                  [item.lower]
                else
                  [DabModernBootstrapLiterals.lower(item)]
                end
      lowered.each { |node| block.insert(node) }
    end
  end
end

class DabModernBootstrapElsifClause
  attr_reader :elsif_token, :space_token, :condition, :condition_separator,
              :body, :source_tokens, :source_parts, :source_span

  def initialize(
    elsif_token:,
    space_token:,
    condition:,
    condition_separator:,
    body:,
    end_location:
  )
    @elsif_token = elsif_token
    @space_token = space_token
    @condition = condition
    @condition_separator = condition_separator
    @body = body.freeze
    @source_tokens = [
      elsif_token,
      space_token,
      condition_token,
      condition_separator,
    ].freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: elsif_token.source_span.start_location,
      end_location: end_location
    )
    freeze
  end

private

  def condition_token
    condition.is_a?(DabModernBootstrapLocalReference) ? condition.name_token : condition
  end
end

class DabModernBootstrapUnlessStatement
  attr_reader :unless_token, :space_token, :condition, :condition_separator,
              :unless_body, :else_token, :else_separator, :else_body,
              :end_token, :final_separator, :source_tokens, :source_parts,
              :source_span

  def initialize(
    unless_token:,
    space_token:,
    condition:,
    condition_separator:,
    unless_body:,
    else_token:,
    else_separator:,
    else_body:,
    end_token:,
    final_separator:
  )
    @unless_token = unless_token
    @space_token = space_token
    @condition = condition
    @condition_separator = condition_separator
    @unless_body = unless_body.freeze
    @else_token = else_token
    @else_separator = else_separator
    @else_body = else_body&.freeze
    @end_token = end_token
    @final_separator = final_separator
    @source_tokens = [
      unless_token,
      space_token,
      condition_token,
      condition_separator,
      else_token,
      else_separator,
      end_token,
      final_separator,
    ].compact.freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: unless_token.source_span.start_location,
      end_location: final_separator.source_span.end_location
    )
    freeze
  end

  def kind
    :unless_statement
  end

  def branch_items
    unless_body + (else_body || [])
  end

  def branch_item_groups
    [unless_body, else_body].compact.freeze
  end

  def lower
    DabNodeIf.new(
      lower_condition,
      lower_branch(else_body || []),
      lower_branch(unless_body)
    ).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end

private

  def condition_token
    condition.is_a?(DabModernBootstrapLocalReference) ? condition.name_token : condition
  end

  def lower_condition
    return condition.lower if condition.is_a?(DabModernBootstrapLocalReference)

    DabModernBootstrapLiterals.lower(condition, consumed: true)
  end

  def lower_branch(items)
    DabNodeTreeBlock.new.tap do |block|
      items.each do |item|
        lowered = if item.is_a?(DabModernBootstrapDirectCall)
                    item.lower_body_items
                  elsif item.respond_to?(:lower)
                    [item.lower]
                  else
                    [DabModernBootstrapLiterals.lower(item)]
                  end
        lowered.each { |node| block.insert(node) }
      end
    end
  end
end

class DabModernBootstrapIfStatement
  attr_reader :if_token, :space_token, :condition, :condition_separator,
              :if_true, :elsif_clauses, :else_token, :else_separator, :if_false,
              :end_token, :final_separator, :source_tokens, :source_parts,
              :source_span

  def initialize(
    if_token:,
    space_token:,
    condition:,
    condition_separator:,
    if_true:,
    elsif_clauses:,
    else_token:,
    else_separator:,
    if_false:,
    end_token:,
    final_separator:
  )
    @if_token = if_token
    @space_token = space_token
    @condition = condition
    @condition_separator = condition_separator
    @if_true = if_true.freeze
    @elsif_clauses = elsif_clauses.freeze
    @else_token = else_token
    @else_separator = else_separator
    @if_false = if_false&.freeze
    @end_token = end_token
    @final_separator = final_separator
    @source_tokens = [
      if_token,
      space_token,
      condition_token,
      condition_separator,
      *elsif_clauses.flat_map(&:source_tokens),
      else_token,
      else_separator,
      end_token,
      final_separator,
    ].compact.freeze
    @source_parts = source_tokens.map(&:source_string).freeze
    @source_span = DabSourceSpan.new(
      start_location: if_token.source_span.start_location,
      end_location: final_separator.source_span.end_location
    )
    freeze
  end

  def kind
    :if_statement
  end

  def branch_items
    if_true + elsif_clauses.flat_map(&:body) + (if_false || [])
  end

  def branch_item_groups
    [if_true, *elsif_clauses.map(&:body), if_false].compact.freeze
  end

  def lower
    false_branch = if elsif_clauses.empty?
                     if_false && lower_branch(if_false)
                   else
                     lower_elsif_tail
                   end
    DabNodeIf.new(
      lower_condition,
      lower_branch(if_true),
      false_branch
    ).tap do |node|
      node.add_source_parts(*source_parts)
    end
  end

private

  def condition_token
    condition.is_a?(DabModernBootstrapLocalReference) ? condition.name_token : condition
  end

  def lower_condition
    lower_condition_value(condition)
  end

  def lower_condition_value(value)
    return value.lower if value.is_a?(DabModernBootstrapLocalReference)

    DabModernBootstrapLiterals.lower(value, consumed: true)
  end

  def lower_elsif_tail
    tail = if_false && lower_branch(if_false)
    elsif_clauses.reverse_each do |clause|
      nested = DabNodeIf.new(
        lower_condition_value(clause.condition),
        lower_branch(clause.body),
        tail
      )
      tail = DabNodeTreeBlock.new.tap { |block| block.insert(nested) }
    end
    tail
  end

  def lower_branch(items)
    DabNodeTreeBlock.new.tap do |block|
      items.each do |item|
        lowered = if item.is_a?(DabModernBootstrapDirectCall)
                    item.lower_body_items
                  elsif item.respond_to?(:lower)
                    [item.lower]
                  else
                    [DabModernBootstrapLiterals.lower(item)]
                  end
        lowered.each { |node| block.insert(node) }
      end
    end
  end
end

class DabModernBootstrapDirectCall
  attr_reader :callable_name, :arguments, :source_span, :source_tokens

  def initialize(callable_name:, arguments:, source_tokens:, closing_parenthesis:)
    @callable_name = callable_name
    @arguments = arguments.freeze
    @source_tokens = source_tokens.freeze
    @source_span = DabSourceSpan.new(
      start_location: callable_name.source_span.start_location,
      end_location: closing_parenthesis.source_span.end_location
    )
    freeze
  end

  def kind
    :direct_call
  end

  def lower
    lower_call(arguments)
  end

  def lower_body_items
    return [lower] unless literal_only_print? && arguments.length != 1

    arguments.map { |argument| lower_call([argument]) }
  end

  def member_result_argument?
    arguments.any? { |argument| argument.is_a?(DabModernBootstrapLiteralMemberCall) }
  end

  def local_reference_argument?
    arguments.any? { |argument| argument.is_a?(DabModernBootstrapLocalReference) }
  end

  def call_result_argument?
    arguments.any? { |argument| argument.is_a?(DabModernBootstrapDirectCall) }
  end

private

  def lower_call(call_arguments)
    DabNodeCall.new(
      callable_name.source_string,
      call_arguments.map { |argument| lower_argument(argument) },
      nil
    ).tap do |node|
      node.add_source_parts(*source_tokens.map(&:source_string))
    end
  end

  def literal_only_print?
    callable_name.text == 'print' && arguments.all? do |argument|
      argument.is_a?(DabModernBootstrapToken)
    end
  end

  def lower_argument(argument)
    return argument.lower(consumed: true) if argument.is_a?(DabModernBootstrapLiteralMemberCall)
    if argument.is_a?(DabModernBootstrapLocalReference) ||
       argument.is_a?(DabModernBootstrapDirectCall)
      return argument.lower
    end

    DabModernBootstrapLiterals.lower(argument, consumed: true)
  end
end

class DabModernBootstrapLiteralMemberCall
  RECEIVER_TYPE_NAMES = {
    nil: 'NilClass',
    boolean_true: 'Boolean',
    boolean_false: 'Boolean',
    integer: 'Fixnum',
    string: 'String',
    regex_literal: 'Regex',
  }.freeze

  attr_reader :receiver_token, :dot_token, :callable_name, :arguments, :source_span, :source_tokens

  def initialize(receiver_token:, dot_token:, callable_name:, arguments:, source_tokens:, closing_parenthesis: nil)
    @receiver_token = receiver_token
    @dot_token = dot_token
    @callable_name = callable_name
    @arguments = arguments.freeze
    @source_tokens = source_tokens.freeze
    @closing_parenthesis = closing_parenthesis
    @source_span = DabSourceSpan.new(
      start_location: receiver_token.source_span.start_location,
      end_location: (closing_parenthesis || callable_name).source_span.end_location
    )
    freeze
  end

  def kind
    :literal_member_call
  end

  def property_style?
    @closing_parenthesis.nil?
  end

  def receiver_type_name
    RECEIVER_TYPE_NAMES.fetch(receiver_token.kind)
  end

  def lower(consumed: false)
    receiver = DabModernBootstrapLiterals.lower(receiver_token)
    arguments = @arguments.map { |argument| DabModernBootstrapLiterals.lower(argument) }
    call = if property_style?
             DabNodePropertyGet.new(receiver, callable_name.source_string)
           else
             DabNodeInstanceCall.new(receiver, callable_name.source_string, arguments, nil)
           end
    call.add_source_parts(*source_tokens.map(&:source_string))
    return call unless approved_result_value?

    DabNodeModernMemberResult.new(call, consumed: consumed).tap do |result|
      result.add_source_parts(*result_source_parts)
    end
  end

private

  def approved_result_value?
    receiver_type_name == 'String' && callable_name.text == 'length' && arguments.empty?
  end

  def result_source_parts
    represented_tokens = [receiver_token, callable_name.base_token, callable_name.suffix_token, *arguments].compact
    source_tokens.reject { |token| represented_tokens.include?(token) }.map(&:source_string)
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
  EXPECT_INTERPOLATION_IDENTIFIER_MESSAGE =
    'invalid Modern String interpolation: expected an ASCII local identifier immediately after "#{"'.freeze
  EXPECT_INTERPOLATION_CLOSE_MESSAGE =
    'invalid Modern String interpolation: expected "}" immediately after local identifier'.freeze
  INTERPOLATION_RESERVED_NAMES = %w[def end return nil true false].freeze

  def initialize(content, nl_is_whitespace = true, source_unit:)
    super(content.b, nl_is_whitespace, source_unit: source_unit)
  end

  def next_token(value_entry: false)
    start_offset = position
    return token(:eof, '', start_offset) if eof?

    case current_char
    when ' '
      advance!
      token(:space, ' ', start_offset)
    when "\t"
      advance!
      token(:tab, "\t", start_offset)
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
    when '('
      advance!
      token(:left_parenthesis, '(', start_offset)
    when ')'
      advance!
      token(:right_parenthesis, ')', start_offset)
    when ','
      advance!
      token(:comma, ',', start_offset)
    when ':'
      advance!
      token(:colon, ':', start_offset)
    when '='
      advance!
      token(:equal, '=', start_offset)
    when '.'
      advance!
      token(:dot, '.', start_offset)
    when '?'
      advance!
      token(:question_mark, '?', start_offset)
    when '!'
      advance!
      token(:bang, '!', start_offset)
    when '"'
      string_token(start_offset)
    when '#'
      line_comment_token(start_offset)
    when '/'
      return regex_literal_token(start_offset) if value_entry

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

  def regex_literal_token(start_offset)
    opening = string_part_token(:regex_delimiter, '/'.b, start_offset, start_offset + 1)
    advance!
    body_start_offset = position

    loop do
      if eof?
        return unsupported_token(
          position,
          0,
          diagnostic_message: 'unterminated Modern regular-expression literal: ' \
                              'expected closing "/" before end of file'
        )
      end

      marker_offset = position
      case current_char
      when '/'
        body = string_part_token(
          :regex_body,
          content.byteslice(body_start_offset, marker_offset - body_start_offset) || ''.b,
          body_start_offset,
          marker_offset
        )
        closing = string_part_token(:regex_delimiter, '/'.b, marker_offset, marker_offset + 1)
        advance!
        source = DabModernBootstrapRegexLiteralSource.new(
          opening: opening,
          body: body,
          closing: closing
        )
        return token(
          :regex_literal,
          content.byteslice(start_offset, position - start_offset),
          start_offset,
          value: source
        )
      when "\n"
        return unsupported_token(
          marker_offset,
          1,
          diagnostic_message: 'invalid Modern regular-expression literal: literal LF is not allowed'
        )
      when "\r"
        length = current_char(1) == "\n" ? 2 : 1
        ending = length == 2 ? 'CRLF' : 'CR'
        return unsupported_token(
          marker_offset,
          length,
          diagnostic_message: "invalid Modern regular-expression literal: literal #{ending} is not allowed"
        )
      when '\\'
        advance!
        if eof?
          return unsupported_token(
            marker_offset,
            1,
            diagnostic_message: 'unterminated Modern regular-expression literal escape: ' \
                                'expected one byte after "\\\\" before end of file'
          )
        end

        if current_char == "\n"
          return unsupported_token(
            marker_offset,
            2,
            diagnostic_message: 'invalid Modern regular-expression literal escape: ' \
                                'line continuation is not allowed'
          )
        end
        if current_char == "\r"
          length = current_char(1) == "\n" ? 3 : 2
          return unsupported_token(
            marker_offset,
            length,
            diagnostic_message: 'invalid Modern regular-expression literal escape: ' \
                                'line continuation is not allowed'
          )
        end

        advance!
      else
        advance!
      end
    end
  end

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
           when 'return' then :return
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
    parts = []
    segment_start_offset = start_offset + 1
    opening_quote = string_part_token(:string_quote, '"'.b, start_offset, start_offset + 1)
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
        closing_offset = position
        raw << current_char
        advance!
        return token(:string, raw, start_offset, value: value) if parts.empty?

        parts << string_part_token(:string_text, raw.byteslice(segment_start_offset - start_offset, closing_offset - segment_start_offset), segment_start_offset, closing_offset, value: value)
        closing_quote = string_part_token(:string_quote, '"'.b, closing_offset, closing_offset + 1)
        interpolation = DabModernBootstrapInterpolatedString.new(
          opening_quote: opening_quote,
          parts: parts,
          closing_quote: closing_quote
        )
        return token(:interpolated_string, raw, start_offset, value: interpolation)
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
          segment_text = content.byteslice(segment_start_offset, marker_offset - segment_start_offset) || ''.b
          parts << string_part_token(
            :string_text,
            segment_text,
            segment_start_offset,
            marker_offset,
            value: value
          )
          value = +''.b

          raw << '#{'.b
          opener = string_part_token(:interpolation_opener, '#{'.b, marker_offset, marker_offset + 2)
          advance!(2)

          name_start = position
          unless IDENTIFIER_START.include?(current_char)
            return interpolation_structure_error(name_start, EXPECT_INTERPOLATION_IDENTIFIER_MESSAGE)
          end

          name = +''.b
          while !eof? && IDENTIFIER_CONTINUE.include?(current_char)
            name << current_char
            raw << current_char
            advance!
          end
          if INTERPOLATION_RESERVED_NAMES.include?(name)
            return unsupported_token(
              name_start,
              name.bytesize,
              diagnostic_message: EXPECT_INTERPOLATION_IDENTIFIER_MESSAGE
            )
          end
          name_token = string_part_token(:identifier, name, name_start, position)

          unless current_char == '}'
            return interpolation_structure_error(position, EXPECT_INTERPOLATION_CLOSE_MESSAGE)
          end

          closer_offset = position
          raw << '}'.b
          advance!
          closer = string_part_token(:interpolation_closer, '}'.b, closer_offset, closer_offset + 1)
          parts << DabModernBootstrapInterpolationSplice.new(
            opener_token: opener,
            name_token: name_token,
            closer_token: closer
          )
          segment_start_offset = position
          next
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

  def interpolation_structure_error(offset, message)
    if current_char == "\n"
      return unsupported_token(
        offset,
        diagnostic_message: 'invalid Modern String literal: literal LF is not allowed; use "\\n"'
      )
    end
    if current_char == "\r"
      return unsupported_token(
        offset,
        diagnostic_message: 'invalid Modern String literal: literal CR is not allowed; use "\\r"'
      )
    end
    if current_char == "\0"
      return unsupported_token(
        offset,
        diagnostic_message: 'invalid Modern String literal: NUL is not allowed'
      )
    end
    if !eof? && content.getbyte(offset) >= 0x80 && !utf8_sequence_length(offset)
      message = sprintf('invalid UTF-8 byte 0x%02X in Modern String literal', content.getbyte(offset))
      return unsupported_token(offset, diagnostic_message: message)
    end

    length = eof? ? 0 : (utf8_sequence_length(offset) || 1)
    unsupported_token(offset, length, diagnostic_message: message)
  end

  def string_part_token(kind, text, start_offset, end_offset, value: text)
    DabModernBootstrapToken.new(
      kind: kind,
      text: text,
      value: value,
      source_span: source_span(start_offset, end_offset)
    )
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

class DabModernBootstrapFunctionDeclaration
  attr_reader :source_unit, :source_span, :callable_name, :parameters, :return_type, :body_items

  def initialize(
    def_token:,
    callable_name:,
    parameters:,
    return_type:,
    header_tokens:,
    body_items:,
    end_token:,
    final_separator:
  )
    @def_token = def_token
    @callable_name = callable_name
    @parameters = parameters.freeze
    @return_type = return_type
    @header_tokens = header_tokens.freeze
    @body_items = body_items.freeze
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
    @body_items.each do |body_item|
      if body_item.is_a?(DabModernBootstrapDirectCall)
        body_item.lower_body_items.each { |lowered_item| body.insert(lowered_item) }
      else
        body.insert(lower_body_item(body_item))
      end
    end
    arglist = DabNode.new
    @parameters.each_with_index do |parameter, index|
      arglist.insert(parameter.lower(index))
    end
    function = DabNodeFunction.new(
      @callable_name.source_string,
      body,
      arglist,
      false,
      nil,
      @return_type&.lower
    )
    function.add_source_parts(
      @def_token.source_string,
      *@callable_name.source_parts,
      *@header_tokens.map(&:source_string),
      @end_token.source_string
    )
    unit.add_function(function)
    function
  end

  def body_tokens
    body_items
  end

private

  def lower_body_item(body_item)
    if body_item.is_a?(DabModernBootstrapIfStatement) ||
       body_item.is_a?(DabModernBootstrapUnlessStatement) ||
       body_item.is_a?(DabModernBootstrapWhileStatement) ||
       body_item.is_a?(DabModernBootstrapCaseStatement) ||
       body_item.is_a?(DabModernBootstrapPostfixGuard)
      return body_item.lower
    end
    if body_item.is_a?(DabModernBootstrapBareReturn) ||
       body_item.is_a?(DabModernBootstrapValueReturn) ||
       body_item.is_a?(DabModernBootstrapBreak) ||
       body_item.is_a?(DabModernBootstrapNext)
      return body_item.lower
    end
    if body_item.is_a?(DabModernBootstrapLiteralMemberCall)
      return body_item.lower
    end
    if body_item.is_a?(DabModernBootstrapLocalBinding) ||
       body_item.is_a?(DabModernBootstrapMutableLocalBinding) ||
       body_item.is_a?(DabModernBootstrapLocalReassignment)
      return body_item.lower
    end

    DabModernBootstrapLiterals.lower(body_item)
  end
end

class DabModernBootstrapDocument
  MEMBER_RESULT_TYPE_NAMES = %w[Int32 Object].freeze
  INT32_MAX = (1 << 31) - 1

  attr_reader :source_unit, :source_span, :declarations

  def initialize(declarations)
    unless declarations.is_a?(Array) && !declarations.empty?
      raise ArgumentError.new('Modern bootstrap document requires one or more declarations')
    end

    @declarations = declarations.freeze
    @source_unit = declarations.fetch(0).source_unit
    unless declarations.all? { |declaration| declaration.source_unit.equal?(@source_unit) }
      raise ArgumentError.new('Modern bootstrap declarations must share one DabSourceUnit identity')
    end

    @source_span = DabSourceSpan.new(
      start_location: declarations.fetch(0).source_span.start_location,
      end_location: declarations.fetch(-1).source_span.end_location
    )
    @bindings_by_reference = preflight_locals!.freeze
    preflight_case_subject_calls!
    preflight_regex_case_subjects!
    freeze
  end

  def lower_into(unit)
    unless unit.is_a?(DabNodeUnit)
      raise ArgumentError.new('Modern bootstrap lowering requires a DabNodeUnit')
    end

    preflight_names!(unit)
    preflight_calls!(unit)
    functions = @declarations.map { |declaration| declaration.lower_into(unit) }
    functions.one? ? functions.fetch(0) : functions.freeze
  end

private

  def preflight_locals!
    bindings_by_reference = {}
    @declarations.each do |declaration|
      parameters_by_name = declaration.parameters.to_h { |parameter| [parameter.name, parameter] }
      bindings = {}
      preflight_body_items!(
        declaration.body_items,
        declaration,
        bindings,
        bindings_by_reference,
        parameters_by_name
      )
    end
    bindings_by_reference
  end

  def preflight_body_items!(
    body_items,
    declaration,
    bindings,
    bindings_by_reference,
    parameters_by_name,
    while_context: nil,
    case_clause: false
  )
    body_items.each do |body_item|
      case body_item
      when DabModernBootstrapCaseStatement
        preflight_case_subject!(
          body_item.subject,
          bindings,
          bindings_by_reference,
          parameters_by_name
        )
        body_item.when_clauses.each do |clause|
          clause.patterns.each do |pattern|
            preflight_interpolations!(pattern, bindings, parameters_by_name)
          end
          preflight_body_items!(
            clause.body,
            declaration,
            duplicate_bindings(bindings),
            bindings_by_reference,
            parameters_by_name,
            while_context: descend_while_context(while_context),
            case_clause: true
          )
        end
        if body_item.else_clause
          preflight_body_items!(
            body_item.else_clause.body,
            declaration,
            duplicate_bindings(bindings),
            bindings_by_reference,
            parameters_by_name,
            while_context: descend_while_context(while_context),
            case_clause: true
          )
        end
      when DabModernBootstrapWhileStatement
        preflight_if_condition!(
          body_item.condition,
          bindings,
          bindings_by_reference,
          parameters_by_name,
          DabModernBootstrapParser::EXPECT_WHILE_CONDITION_MESSAGE
        )
        loop_guard_name = eligible_loop_guard_name(body_item.condition, bindings)
        preflight_body_items!(
          body_item.loop_items,
          declaration,
          duplicate_bindings(bindings),
          bindings_by_reference,
          parameters_by_name,
          while_context: {guard_name: loop_guard_name, immediate: true}.freeze,
          case_clause: case_clause
        )
      when DabModernBootstrapPostfixGuard
        expectation_message = if body_item.keyword_token.text == 'if'
                                DabModernBootstrapParser::EXPECT_POSTFIX_IF_CONDITION_MESSAGE
                              else
                                DabModernBootstrapParser::EXPECT_POSTFIX_UNLESS_CONDITION_MESSAGE
                              end
        preflight_if_condition!(
          body_item.condition,
          bindings,
          bindings_by_reference,
          parameters_by_name,
          expectation_message
        )
        preflight_body_items!(
          body_item.branch_items,
          declaration,
          duplicate_bindings(bindings),
          bindings_by_reference,
          parameters_by_name,
          while_context: descend_while_context(while_context),
          case_clause: case_clause
        )
      when DabModernBootstrapBreak
        unless while_context
          raise DabModernBootstrapParseError.new(
            DabModernBootstrapParser::UNEXPECTED_BREAK_MESSAGE,
            source_span: body_item.source_span
          )
        end
      when DabModernBootstrapNext
        unless while_context
          raise DabModernBootstrapParseError.new(
            DabModernBootstrapParser::UNEXPECTED_NEXT_MESSAGE,
            source_span: body_item.source_span
          )
        end
      when DabModernBootstrapIfStatement
        preflight_if_condition!(
          body_item.condition,
          bindings,
          bindings_by_reference,
          parameters_by_name,
          DabModernBootstrapParser::EXPECT_IF_CONDITION_MESSAGE
        )
        preflight_body_items!(
          body_item.if_true,
          declaration,
          duplicate_bindings(bindings),
          bindings_by_reference,
          parameters_by_name,
          while_context: descend_while_context(while_context),
          case_clause: case_clause
        )
        body_item.elsif_clauses.each do |clause|
          preflight_if_condition!(
            clause.condition,
            bindings,
            bindings_by_reference,
            parameters_by_name,
            DabModernBootstrapParser::EXPECT_ELSIF_CONDITION_MESSAGE
          )
          preflight_body_items!(
            clause.body,
            declaration,
            duplicate_bindings(bindings),
            bindings_by_reference,
            parameters_by_name,
            while_context: descend_while_context(while_context),
            case_clause: case_clause
          )
        end
        if body_item.if_false
          preflight_body_items!(
            body_item.if_false,
            declaration,
            duplicate_bindings(bindings),
            bindings_by_reference,
            parameters_by_name,
            while_context: descend_while_context(while_context),
            case_clause: case_clause
          )
        end
      when DabModernBootstrapUnlessStatement
        preflight_if_condition!(
          body_item.condition,
          bindings,
          bindings_by_reference,
          parameters_by_name,
          DabModernBootstrapParser::EXPECT_UNLESS_CONDITION_MESSAGE
        )
        body_item.branch_item_groups.each do |group|
          preflight_body_items!(
            group,
            declaration,
            duplicate_bindings(bindings),
            bindings_by_reference,
            parameters_by_name,
            while_context: descend_while_context(while_context),
            case_clause: case_clause
          )
        end
      when DabModernBootstrapLocalBinding, DabModernBootstrapMutableLocalBinding
        reject_case_clause_binding!(body_item) if case_clause
        reject_while_binding!(body_item) if while_context
        preflight_local_binding!(body_item, bindings, parameters_by_name)
        preflight_interpolations!(body_item, bindings, parameters_by_name)
        preflight_typed_local_initializer!(body_item)
        bindings[body_item.name] = {
          declaration: body_item,
          latest_write: body_item,
        }
      when DabModernBootstrapLocalReassignment
        reject_case_clause_reassignment!(body_item) if case_clause
        preflight_while_reassignment!(body_item, bindings, while_context) if while_context
        binding = bindings[body_item.name]
        unless binding
          raise DabModernBootstrapParseError.new(source_span: body_item.name_token.source_span)
        end

        binding_declaration = binding.fetch(:declaration)
        if binding_declaration.is_a?(DabModernBootstrapLocalBinding)
          raise DabModernBootstrapParseError.new(
            %(cannot reassign Modern let binding "#{body_item.name}"),
            source_span: body_item.name_token.source_span
          )
        end
        unless binding_declaration.is_a?(DabModernBootstrapMutableLocalBinding)
          raise DabModernBootstrapParseError.new(source_span: body_item.name_token.source_span)
        end

        preflight_interpolations!(body_item, bindings, parameters_by_name)
        preflight_typed_local_write!(body_item, binding_declaration)
        binding[:latest_write] = body_item
      when DabModernBootstrapValueReturn
        unless body_item.value.is_a?(DabModernBootstrapDirectCall)
          preflight_interpolations!(body_item, bindings, parameters_by_name)
        end
        preflight_ring_independent_return!(
          body_item,
          declaration,
          bindings,
          bindings_by_reference,
          parameters_by_name
        )
        if body_item.value.is_a?(DabModernBootstrapDirectCall)
          preflight_call_values!(
            body_item.value,
            bindings,
            bindings_by_reference,
            parameters_by_name
          )
        end
      when DabModernBootstrapDirectCall
        preflight_call_values!(body_item, bindings, bindings_by_reference, parameters_by_name)
      else
        preflight_interpolations!(body_item, bindings, parameters_by_name)
      end
    end
  end

  def duplicate_bindings(bindings)
    bindings.transform_values(&:dup)
  end

  def descend_while_context(while_context)
    return unless while_context

    {guard_name: while_context.fetch(:guard_name), immediate: false}.freeze
  end

  def eligible_loop_guard_name(condition, bindings)
    return unless condition.is_a?(DabModernBootstrapLocalReference)

    binding = bindings[condition.name]
    return unless binding
    return unless binding.fetch(:declaration).is_a?(DabModernBootstrapMutableLocalBinding)

    condition.name
  end

  def reject_while_binding!(binding)
    token = if binding.is_a?(DabModernBootstrapLocalBinding)
              binding.let_token
            else
              binding.var_token
            end
    raise DabModernBootstrapParseError.new(
      DabModernBootstrapParser::WHILE_BODY_BINDING_MESSAGE,
      source_span: token.source_span
    )
  end

  def reject_case_clause_binding!(binding)
    token = if binding.is_a?(DabModernBootstrapLocalBinding)
              binding.let_token
            else
              binding.var_token
            end
    raise DabModernBootstrapParseError.new(
      DabModernBootstrapParser::CASE_CLAUSE_BINDING_MESSAGE,
      source_span: token.source_span
    )
  end

  def reject_case_clause_reassignment!(reassignment)
    raise DabModernBootstrapParseError.new(
      DabModernBootstrapParser::CASE_CLAUSE_REASSIGNMENT_MESSAGE,
      source_span: reassignment.name_token.source_span
    )
  end

  def preflight_while_reassignment!(reassignment, bindings, while_context)
    eligible = while_context.fetch(:immediate) &&
               reassignment.name == while_context.fetch(:guard_name) &&
               bindings.key?(reassignment.name)
    unless eligible
      raise DabModernBootstrapParseError.new(
        DabModernBootstrapParser::WHILE_BODY_REASSIGNMENT_MESSAGE,
        source_span: reassignment.name_token.source_span
      )
    end

    value = reassignment.value_token
    return if value.is_a?(DabModernBootstrapToken) &&
              %i[boolean_true boolean_false].include?(value.kind)

    raise DabModernBootstrapParseError.new(
      DabModernBootstrapParser::EXPECT_WHILE_GUARD_REASSIGNMENT_VALUE_MESSAGE,
      source_span: value.source_span
    )
  end

  def preflight_if_condition!(
    condition,
    bindings,
    bindings_by_reference,
    parameters_by_name,
    expectation_message
  )
    return if condition.is_a?(DabModernBootstrapToken)

    binding = bindings[condition.name]
    parameter = parameters_by_name[condition.name]
    actual_type = if binding
                    binding.fetch(:latest_write).initializer_type
                  elsif parameter
                    DabType.parse(parameter.type_name.text)
                  end
    unless actual_type&.type_string == 'Boolean'
      raise DabModernBootstrapParseError.new(
        expectation_message,
        source_span: condition.source_span
      )
    end
    bindings_by_reference[condition] = actual_type
  end

  def preflight_case_subject!(subject, bindings, bindings_by_reference, parameters_by_name)
    if subject.is_a?(DabModernBootstrapDirectCall)
      preflight_call_values!(subject, bindings, bindings_by_reference, parameters_by_name)
      return
    end

    if subject.is_a?(DabModernBootstrapLocalReference)
      binding = bindings[subject.name]
      parameter = parameters_by_name[subject.name]
      unless binding || parameter
        raise DabModernBootstrapParseError.new(
          DabModernBootstrapParser::EXPECT_CASE_SUBJECT_MESSAGE,
          source_span: subject.source_span
        )
      end

      bindings_by_reference[subject] = if binding
                                         declaration = binding.fetch(:declaration)
                                         if declaration.annotated?
                                           declaration.declared_type
                                         else
                                           binding.fetch(:latest_write).initializer_type
                                         end
                                       else
                                         DabType.parse(parameter.type_name.text)
                                       end
    end

    preflight_interpolations!(subject, bindings, parameters_by_name)
  end

  def preflight_interpolations!(value, bindings, parameters_by_name)
    interpolation_tokens(value).each do |token|
      token.value.splices.each do |splice|
        name = splice.name
        binding = bindings[name]
        if binding
          actual_type = binding.fetch(:latest_write).initializer_type
          next if actual_type.type_string == 'String'

          raise DabModernBootstrapParseError.new(
            "cannot interpolate Modern local \"#{name}\" of type #{actual_type.type_string}; " \
            'simple interpolation requires exact String',
            source_span: splice.name_token.source_span
          )
        end

        parameter = parameters_by_name[name]
        unless parameter
          raise DabModernBootstrapParseError.new(
            "unknown Modern interpolation local \"#{name}\"; expected an earlier same-function local binding",
            source_span: splice.name_token.source_span
          )
        end

        actual_type = DabType.parse(parameter.type_name.text)
        next if actual_type.type_string == 'String'

        raise DabModernBootstrapParseError.new(
          "cannot interpolate Modern parameter \"#{name}\" of type #{actual_type.type_string}; " \
          'simple interpolation requires exact String',
          source_span: splice.name_token.source_span
        )
      end
    end
  end

  def interpolation_tokens(value)
    if value.is_a?(DabModernBootstrapToken)
      return value.kind == :interpolated_string ? [value] : []
    end
    if value.is_a?(DabModernBootstrapLocalBinding) ||
       value.is_a?(DabModernBootstrapMutableLocalBinding)
      return interpolation_tokens(value.initializer_token)
    end
    if value.is_a?(DabModernBootstrapLocalReassignment)
      return interpolation_tokens(value.value_token)
    end
    if value.is_a?(DabModernBootstrapValueReturn)
      return interpolation_tokens(value.value)
    end
    if value.is_a?(DabModernBootstrapDirectCall)
      return value.arguments.flat_map { |argument| interpolation_tokens(argument) }
    end
    if value.is_a?(DabModernBootstrapIfStatement) ||
       value.is_a?(DabModernBootstrapUnlessStatement)
      return value.branch_items.flat_map { |item| interpolation_tokens(item) }
    end
    if value.is_a?(DabModernBootstrapWhileStatement)
      return value.loop_items.flat_map { |item| interpolation_tokens(item) }
    end
    if value.is_a?(DabModernBootstrapPostfixGuard)
      return interpolation_tokens(value.guarded_item)
    end

    if value.is_a?(DabModernBootstrapCaseStatement)
      clause_tokens = value.when_clauses.flat_map do |clause|
        clause.patterns.flat_map { |pattern| interpolation_tokens(pattern) } +
          clause.body.flat_map { |item| interpolation_tokens(item) }
      end
      else_tokens = value.else_clause&.body&.flat_map { |item| interpolation_tokens(item) } || []
      return interpolation_tokens(value.subject) + clause_tokens + else_tokens
    end

    []
  end

  def preflight_ring_independent_return!(
    value_return,
    function,
    bindings,
    bindings_by_reference,
    parameters_by_name
  )
    value = value_return.value
    return if value.is_a?(DabModernBootstrapLiteralMemberCall) ||
              value.is_a?(DabModernBootstrapDirectCall)

    actual_type = if value.is_a?(DabModernBootstrapLocalReference)
                    binding = bindings[value.name]
                    parameter = parameters_by_name[value.name]
                    unless binding || parameter
                      raise DabModernBootstrapParseError.new(source_span: value.source_span)
                    end

                    type = if binding
                             binding_declaration = binding.fetch(:declaration)
                             if binding_declaration.annotated?
                               binding_declaration.declared_type
                             else
                               binding.fetch(:latest_write).initializer_type
                             end
                           else
                             DabType.parse(parameter.type_name.text)
                           end
                    bindings_by_reference[value] = type
                    type
                  else
                    DabModernBootstrapLiterals.flow_type(value)
                  end
    preflight_return_type!(value_return, function, actual_type)
  end

  def preflight_call_values!(call, bindings, bindings_by_reference, parameters_by_name)
    call.arguments.each do |argument|
      if argument.is_a?(DabModernBootstrapDirectCall)
        preflight_call_values!(argument, bindings, bindings_by_reference, parameters_by_name)
        next
      end
      if argument.is_a?(DabModernBootstrapToken) && argument.kind == :interpolated_string
        preflight_interpolations!(argument, bindings, parameters_by_name)
        next
      end
      next unless argument.is_a?(DabModernBootstrapLocalReference)

      binding = bindings[argument.name]
      parameter = parameters_by_name[argument.name]
      unless binding || parameter
        raise DabModernBootstrapParseError.new(source_span: argument.source_span)
      end

      bindings_by_reference[argument] = if binding
                                          declaration = binding.fetch(:declaration)
                                          if declaration.annotated?
                                            declaration.declared_type
                                          else
                                            binding.fetch(:latest_write).initializer_type
                                          end
                                        else
                                          DabType.parse(parameter.type_name.text)
                                        end
    end
  end

  def preflight_return_type!(value_return, function, actual_type)
    expected_type = DabType.parse(function.return_type&.text)
    return if expected_type.can_assign_from?(actual_type)

    reject_return_type!(value_return, function, actual_type, expected_type)
  end

  def reject_return_type!(value_return, function, actual_type, expected_type)
    raise DabModernBootstrapParseError.new(
      "cannot return Modern value of type #{actual_type.type_string} from function " \
      "\"#{function.callable_name.text}\" with declared return type #{expected_type.type_string}",
      source_span: value_return.value.source_span
    )
  end

  def preflight_local_binding!(binding, bindings, parameters_by_name)
    if bindings.key?(binding.name)
      raise DabModernBootstrapParseError.new(
        %(duplicate Modern local binding "#{binding.name}"),
        source_span: binding.name_token.source_span
      )
    end
    return unless parameters_by_name.key?(binding.name)

    raise DabModernBootstrapParseError.new(
      %(Modern local binding "#{binding.name}" conflicts with parameter "#{binding.name}"),
      source_span: binding.name_token.source_span
    )
  end

  def preflight_typed_local_initializer!(binding)
    return unless binding.annotated?

    declared_type = binding.declared_type
    actual_type = binding.initializer_type
    return if declared_type.can_assign_from?(actual_type)

    raise DabModernBootstrapParseError.new(
      "cannot initialize Modern local \"#{binding.name}\" of type #{declared_type.type_string} " \
      "with literal of type #{actual_type.type_string}",
      source_span: binding.initializer_token.source_span
    )
  end

  def preflight_typed_local_write!(write, declaration)
    return unless declaration.annotated?

    declared_type = declaration.declared_type
    actual_type = write.initializer_type
    return if declared_type.can_assign_from?(actual_type)

    raise DabModernBootstrapParseError.new(
      "cannot assign Modern literal of type #{actual_type.type_string} to local " \
      "\"#{write.name}\" of type #{declared_type.type_string}",
      source_span: write.value_token.source_span
    )
  end

  def preflight_names!(unit)
    seen = {}
    @declarations.each do |declaration|
      name = declaration.callable_name.text
      if seen.key?(name) || unit.has_function?(name)
        raise DabModernBootstrapParseError.new(
          source_span: declaration.callable_name.source_span
        )
      end

      seen[name] = true
    end
  end

  def preflight_calls!(unit)
    declarations_by_name = @declarations.to_h { |declaration| [declaration.callable_name.text, declaration] }
    @declarations.each do |declaration|
      preflight_calls_in_items!(declaration.body_items, declaration, unit, declarations_by_name)
    end
  end

  def preflight_case_subject_calls!
    declarations_by_name = @declarations.to_h { |declaration| [declaration.callable_name.text, declaration] }
    @declarations.each do |declaration|
      each_case_statement(declaration.body_items) do |statement|
        next unless statement.subject.is_a?(DabModernBootstrapDirectCall)

        preflight_ring_independent_case_call!(statement.subject, declarations_by_name)
      end
    end
  end

  def preflight_regex_case_subjects!
    declarations_by_name = @declarations.to_h { |declaration| [declaration.callable_name.text, declaration] }
    @declarations.each do |declaration|
      each_case_statement(declaration.body_items) do |statement|
        next unless statement.when_clauses.any? do |clause|
          clause.patterns.any? { |pattern| DabModernBootstrapLiterals.regex_literal?(pattern) }
        end

        actual_type = regex_case_subject_type(statement.subject, declarations_by_name)
        next if actual_type.instance_of?(DabTypeString)

        raise DabModernBootstrapParseError.new(
          "invalid Modern Regex case subject: expected String, got #{actual_type.type_string}",
          source_span: statement.subject.source_span
        )
      end
    end
  end

  def regex_case_subject_type(subject, declarations_by_name)
    if subject.is_a?(DabModernBootstrapDirectCall)
      target = declarations_by_name.fetch(subject.callable_name.text)
      return DabType.parse(target.return_type&.text)
    end
    if subject.is_a?(DabModernBootstrapLocalReference)
      return @bindings_by_reference.fetch(subject)
    end

    DabModernBootstrapLiterals.flow_type(subject)
  end

  def each_case_statement(items, &block)
    items.each do |item|
      case item
      when DabModernBootstrapCaseStatement
        yield item
        item.when_clauses.each { |clause| each_case_statement(clause.body, &block) }
        each_case_statement(item.else_clause.body, &block) if item.else_clause
      when DabModernBootstrapWhileStatement
        each_case_statement(item.loop_items, &block)
      when DabModernBootstrapPostfixGuard
        each_case_statement(item.branch_items, &block)
      when DabModernBootstrapIfStatement, DabModernBootstrapUnlessStatement
        item.branch_item_groups.each { |group| each_case_statement(group, &block) }
      end
    end
  end

  def preflight_ring_independent_case_call!(call, declarations_by_name)
    target = declarations_by_name[call.callable_name.text]
    unless target
      reject_call(
        call,
        %(unknown Modern call target "#{call.callable_name.text}"),
        call.callable_name.source_span
      )
    end

    preflight_arity!(call, target.parameters.length)
    call.arguments.zip(target.parameters).each do |argument, parameter|
      actual_type = ring_independent_case_argument_type(argument)
      expected_type = DabType.parse(parameter.type_name.text)
      next if expected_type.can_assign_from?(actual_type)

      reject_argument_type!(call, argument, parameter, actual_type)
    end
  end

  def ring_independent_case_argument_type(argument)
    if argument.is_a?(DabModernBootstrapLocalReference)
      return @bindings_by_reference.fetch(argument)
    end

    if argument.is_a?(DabModernBootstrapLiteralMemberCall)
      call = argument
      target = "#{call.receiver_type_name}##{call.callable_name.text}"
      unless target == 'String#length'
        reject_call(
          call,
          %(unknown Modern member target "#{target}"),
          call.callable_name.source_span
        )
      end
      preflight_member_arity!(call, target, 0)
      preflight_member_result_range!(call)
      return DabType.parse('Int32')
    end

    DabModernBootstrapLiterals.flow_type(argument)
  end

  def preflight_calls_in_items!(items, declaration, unit, declarations_by_name)
    items.each do |body_item|
      case body_item
      when DabModernBootstrapCaseStatement
        if body_item.subject.is_a?(DabModernBootstrapDirectCall)
          preflight_call_result!(body_item.subject, unit, declarations_by_name)
        end
        body_item.when_clauses.each do |clause|
          preflight_calls_in_items!(clause.body, declaration, unit, declarations_by_name)
        end
        if body_item.else_clause
          preflight_calls_in_items!(
            body_item.else_clause.body,
            declaration,
            unit,
            declarations_by_name
          )
        end
      when DabModernBootstrapWhileStatement
        preflight_calls_in_items!(body_item.loop_items, declaration, unit, declarations_by_name)
      when DabModernBootstrapPostfixGuard
        preflight_calls_in_items!(body_item.branch_items, declaration, unit, declarations_by_name)
      when DabModernBootstrapIfStatement, DabModernBootstrapUnlessStatement
        body_item.branch_item_groups.each do |group|
          preflight_calls_in_items!(group, declaration, unit, declarations_by_name)
        end
      when DabModernBootstrapDirectCall
        preflight_call!(body_item, unit, declarations_by_name)
      when DabModernBootstrapLiteralMemberCall
        preflight_member_call!(body_item, unit)
      when DabModernBootstrapValueReturn
        if body_item.value.is_a?(DabModernBootstrapLiteralMemberCall)
          preflight_member_return!(body_item, declaration, unit)
        elsif body_item.value.is_a?(DabModernBootstrapDirectCall)
          preflight_call_result_return!(body_item, declaration, unit, declarations_by_name)
        end
      end
    end
  end

  def preflight_member_return!(value_return, function, unit)
    preflight_member_call!(value_return.value, unit)
    return if function.return_type.nil? || function.return_type.text == 'Int32'

    reject_return_type!(
      value_return,
      function,
      DabType.parse('Int32'),
      DabType.parse(function.return_type.text)
    )
  end

  def preflight_member_call!(call, unit)
    receiver = call.receiver_type_name
    receiver_type = DabModernBootstrapLiterals.flow_type(call.receiver_token)
    name = call.callable_name.text
    target = "#{receiver}##{name}"

    if receiver == 'String' && name == 'length'
      if lower_ring_defines_string_length?(unit)
        reject_call(
          call,
          %(unsupported Modern member target "#{target}" in the R40 dot/property-call subset),
          call.callable_name.source_span
        )
      end
      preflight_member_arity!(call, target, 0)
      preflight_member_result_range!(call)
    elsif known_member_target?(unit, receiver, receiver_type, name)
      reject_call(
        call,
        %(unsupported Modern member target "#{target}" in the R40 dot/property-call subset),
        call.callable_name.source_span
      )
    else
      reject_call(call, %(unknown Modern member target "#{target}"), call.callable_name.source_span)
    end
  end

  def preflight_call!(call, unit, declarations_by_name)
    name = call.callable_name.text
    preflight_arity!(call, 1) if name == 'print' && call.local_reference_argument?
    target = declarations_by_name[name]
    if target
      preflight_same_document_call!(call, target, unit, declarations_by_name)
    elsif name == 'print'
      preflight_arity!(call, 1) if call.member_result_argument? || call.call_result_argument?
      preflight_member_arguments!(call, unit)
      preflight_call_result_arguments!(call, unit, declarations_by_name, DabType.parse(nil))
    elsif name == 'puts'
      preflight_puts_call!(call, unit)
      preflight_member_arguments!(call, unit)
      preflight_call_result_arguments!(call, unit, declarations_by_name, DabType.parse(nil))
    elsif known_target?(unit, name)
      reject_call(call, %(unsupported Modern call target "#{name}" in the R39 ordinary-call subset), call.callable_name.source_span)
    else
      reject_call(call, %(unknown Modern call target "#{name}"), call.callable_name.source_span)
    end
  end

  def preflight_same_document_call!(call, target, unit, declarations_by_name)
    expected = target.parameters.length
    preflight_arity!(call, expected)
    call.arguments.zip(target.parameters).each do |argument, parameter|
      if argument.is_a?(DabModernBootstrapDirectCall)
        expected_type = DabType.parse(parameter.type_name.text)
        actual_type = preflight_call_result!(argument, unit, declarations_by_name)
        next if exact_call_result_type?(actual_type, expected_type)

        reject_argument_type!(call, argument, parameter, actual_type)
      end

      if argument.is_a?(DabModernBootstrapLiteralMemberCall)
        preflight_member_call!(argument, unit)
        next if MEMBER_RESULT_TYPE_NAMES.include?(parameter.type_name.text)

        reject_argument_type!(call, argument, parameter, DabType.parse('Int32'))
      end

      actual_type = argument_type(argument)
      expected_type = DabType.parse(parameter.type_name.text)
      next if expected_type.can_assign_from?(actual_type)

      reject_argument_type!(call, argument, parameter, actual_type)
    end
  end

  def preflight_call_result_return!(value_return, function, unit, declarations_by_name)
    actual_type = preflight_call_result!(value_return.value, unit, declarations_by_name)
    expected_type = DabType.parse(function.return_type&.text)
    return if exact_call_result_type?(actual_type, expected_type)

    reject_return_type!(value_return, function, actual_type, expected_type)
  end

  def preflight_call_result_arguments!(call, unit, declarations_by_name, expected_type)
    call.arguments.each do |argument|
      next unless argument.is_a?(DabModernBootstrapDirectCall)

      actual_type = preflight_call_result!(argument, unit, declarations_by_name)
      next if exact_call_result_type?(actual_type, expected_type)

      raise DabModernBootstrapParseError.new(source_span: argument.source_span)
    end
  end

  def preflight_call_result!(call, unit, declarations_by_name)
    name = call.callable_name.text
    target = declarations_by_name[name]
    unless target
      if known_target?(unit, name)
        reject_call(
          call,
          %(unsupported Modern call target "#{name}" in the R39 ordinary-call subset),
          call.callable_name.source_span
        )
      end
      reject_call(call, %(unknown Modern call target "#{name}"), call.callable_name.source_span)
    end

    preflight_same_document_call!(call, target, unit, declarations_by_name)
    DabType.parse(target.return_type&.text)
  end

  def exact_call_result_type?(actual_type, expected_type)
    expected_type.type_string == 'Object' || expected_type.type_string == actual_type.type_string
  end

  def argument_type(argument)
    if argument.is_a?(DabModernBootstrapLocalReference)
      return @bindings_by_reference.fetch(argument)
    end

    DabModernBootstrapLiterals.type(argument)
  end

  def preflight_member_arguments!(call, unit)
    call.arguments.each do |argument|
      preflight_member_call!(argument, unit) if argument.is_a?(DabModernBootstrapLiteralMemberCall)
    end
  end

  def reject_argument_type!(call, argument, parameter, actual_type)
    expected_type = DabType.parse(parameter.type_name.text)
    reject_call(
      call,
      "cannot pass Modern argument of type #{actual_type.type_string} to parameter " \
      "\"#{parameter.name}\" of type #{expected_type.type_string} in call " \
      "\"#{call.callable_name.text}\"",
      argument.source_span
    )
  end

  def preflight_member_result_range!(call)
    return unless call.receiver_token.kind == :string
    return if member_result_byte_count_in_range?(call.receiver_token.value.bytesize)

    reject_call(
      call,
      "Modern String#length result exceeds exact Int32 byte-count range 0..#{INT32_MAX}",
      call.source_span
    )
  end

  def member_result_byte_count_in_range?(byte_count)
    byte_count.between?(0, INT32_MAX)
  end

  def preflight_puts_call!(call, unit)
    target = unit.has_function?('puts')
    unless approved_puts_target?(target)
      reject_call(
        call,
        'unsupported Modern call target "puts" in the R39 ordinary-call subset',
        call.callable_name.source_span
      )
    end

    preflight_arity!(call, 1)
  end

  def preflight_arity!(call, expected)
    actual = call.arguments.length
    return if actual == expected

    reject_call(
      call,
      %(incorrect Modern call arity for "#{call.callable_name.text}": got #{actual}, expected #{expected}),
      call.source_span
    )
  end

  def preflight_member_arity!(call, target, expected)
    actual = call.arguments.length
    return if actual == expected

    reject_call(
      call,
      %(incorrect Modern member-call arity for "#{target}": got #{actual}, expected #{expected}),
      call.source_span
    )
  end

  def approved_puts_target?(target)
    return false unless target.is_a?(DabNodeFunctionStub) && !target.is_static?

    signature = target.ring_signature
    return false unless signature.is_a?(Hash)

    arguments = signature[:arguments]
    return false unless arguments.is_a?(Array) && arguments.one?

    argument = arguments.fetch(0)
    argument.is_a?(Hash) && argument[:type] == 'Object' && signature[:return_type] == 'Object'
  end

  def known_target?(unit, name)
    BUILTINS.include?(name) || unit.has_function?(name) || unit.classes.to_a.any? do |klass|
      klass.functions.to_a.any? { |function| function.identifier.to_s == name }
    end
  end

  def known_member_target?(unit, receiver, receiver_type, name)
    receiver_type.has_function?(name) || unit.classes.to_a.any? do |klass|
      klass.identifier.to_s == receiver && klass.functions.to_a.any? do |function|
        !function.is_static? && function.identifier.to_s == name
      end
    end
  end

  def lower_ring_defines_string_length?(unit)
    unit.classes.to_a.any? do |klass|
      klass.identifier.to_s == 'String' && klass.functions.to_a.any? do |function|
        !function.is_static? && function.identifier.to_s == 'length'
      end
    end
  end

  def reject_call(_call, message, source_span)
    raise DabModernBootstrapParseError.new(message, source_span: source_span)
  end
end

class DabModernBootstrapParser
  SEPARATOR_KINDS = %i[line_feed semicolon line_comment].freeze
  LITERAL_KINDS = %i[nil boolean_true boolean_false integer string].freeze
  VALUE_KINDS = (LITERAL_KINDS + [:interpolated_string]).freeze
  HORIZONTAL_WHITESPACE_KINDS = %i[space tab].freeze
  SUPPORTED_TYPE_NAMES = %w[
    String Fixnum Boolean Uint8 Uint16 Uint32 Uint64
    Int8 Int16 Int32 Int64 IntPtr NilClass Float
  ].freeze
  EXPECT_SPACE_MESSAGE =
    'invalid Modern function declaration: expected one ASCII space after "def"'.freeze
  EXPECT_CALLABLE_NAME_MESSAGE =
    'invalid Modern function declaration: expected a callable name after "def "'.freeze
  EXPECT_NAME_SEPARATOR_MESSAGE =
    'invalid Modern function declaration: expected a separator (LF, semicolon, or line comment) after callable name'.freeze
  EXPECT_LITERAL_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after literal'.freeze
  EXPECT_BARE_RETURN_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after bare return'.freeze
  EXPECT_BREAK_SEPARATOR_MESSAGE =
    'invalid Modern break statement: expected a separator (LF, semicolon, or line comment) after "break"'.freeze
  UNEXPECTED_BREAK_MESSAGE =
    'unexpected Modern "break": no enclosing loop in this function'.freeze
  EXPECT_NEXT_SEPARATOR_MESSAGE =
    'invalid Modern next statement: expected a separator (LF, semicolon, or line comment) after "next"'.freeze
  UNEXPECTED_NEXT_MESSAGE =
    'unexpected Modern "next": no enclosing loop in this function'.freeze
  EXPECT_VALUE_RETURN_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after returned value'.freeze
  EXPECT_END_MESSAGE =
    'unterminated Modern function declaration: expected closing "end" before end of file'.freeze
  EXPECT_END_SEPARATOR_MESSAGE =
    'invalid Modern function declaration: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  UNEXPECTED_END_MESSAGE = 'unexpected Modern "end": no open function declaration'.freeze
  INVALID_CR_SEPARATOR_MESSAGE = 'invalid Modern separator: CR and CRLF are not supported; use LF'.freeze
  EXPECT_PARAMETER_OR_CLOSE_MESSAGE =
    'invalid Modern parameter list: expected a parameter name or closing ")"'.freeze
  EXPECT_PARAMETER_COLON_MESSAGE =
    'invalid Modern parameter declaration: expected ":" after parameter name'.freeze
  EXPECT_PARAMETER_TYPE_MESSAGE =
    'invalid Modern parameter declaration: expected a supported type name after ":"'.freeze
  EXPECT_PARAMETER_SEPARATOR_MESSAGE =
    'invalid Modern parameter list: expected "," or closing ")" after parameter'.freeze
  EXPECT_PARAMETER_AFTER_COMMA_MESSAGE =
    'invalid Modern parameter list: expected a parameter name after ","'.freeze
  EXPECT_PARAMETER_CLOSE_MESSAGE =
    'unterminated Modern parameter list: expected closing ")" before end of file'.freeze
  EXPECT_RETURN_TYPE_MESSAGE =
    'invalid Modern return contract: expected a supported type name after ":"'.freeze
  EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE =
    'invalid Modern call argument list: expected a literal argument or closing ")"'.freeze
  EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE =
    'invalid Modern call argument list: expected "," or closing ")" after argument'.freeze
  EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE =
    'invalid Modern call argument list: expected a literal argument after ","'.freeze
  EXPECT_CALL_CLOSE_MESSAGE =
    'unterminated Modern call: expected closing ")" before end of file'.freeze
  EXPECT_CALL_BODY_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after call'.freeze
  EXPECT_DOT_CALLABLE_NAME_MESSAGE =
    'invalid Modern dot call: expected a callable name immediately after "."'.freeze
  EXPECT_MEMBER_TAIL_MESSAGE =
    'invalid Modern dot/property call: expected "(" or a separator (LF, semicolon, or line comment) after member name'.freeze
  EXPECT_MEMBER_CALL_BODY_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after member call'.freeze
  EXPECT_LET_SPACE_MESSAGE =
    'invalid Modern let binding: expected one ASCII space after "let"'.freeze
  EXPECT_LET_NAME_MESSAGE =
    'invalid Modern let binding: expected a binding name after "let "'.freeze
  EXPECT_LET_EQUAL_MESSAGE =
    'invalid Modern let binding: expected "=" after binding name'.freeze
  EXPECT_LOCAL_TYPE_MESSAGE =
    'invalid Modern local type annotation: expected a supported type name after ":"'.freeze
  EXPECT_TYPED_LET_EQUAL_MESSAGE =
    'invalid Modern let binding: expected "=" after local type annotation'.freeze
  EXPECT_LET_INITIALIZER_MESSAGE =
    'invalid Modern let binding: expected a literal initializer after "="'.freeze
  EXPECT_LET_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after let binding'.freeze
  EXPECT_VAR_SPACE_MESSAGE =
    'invalid Modern var binding: expected one ASCII space after "var"'.freeze
  EXPECT_VAR_NAME_MESSAGE =
    'invalid Modern var binding: expected a binding name after "var "'.freeze
  EXPECT_VAR_EQUAL_MESSAGE =
    'invalid Modern var binding: expected "=" after binding name'.freeze
  EXPECT_TYPED_VAR_EQUAL_MESSAGE =
    'invalid Modern var binding: expected "=" after local type annotation'.freeze
  EXPECT_VAR_INITIALIZER_MESSAGE =
    'invalid Modern var binding: expected a literal initializer after "="'.freeze
  EXPECT_VAR_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after var binding'.freeze
  EXPECT_REASSIGNMENT_VALUE_MESSAGE =
    'invalid Modern local reassignment: expected a literal value after "="'.freeze
  EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE =
    'invalid Modern function body: expected a separator (LF, semicolon, or line comment) after local reassignment'.freeze
  EXPECT_IF_SPACE_MESSAGE =
    'invalid Modern if statement: expected exactly one ASCII space after "if"'.freeze
  EXPECT_IF_CONDITION_MESSAGE =
    'invalid Modern if condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_IF_CONDITION_SEPARATOR_MESSAGE =
    'invalid Modern if statement: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  EXPECT_ELSIF_SPACE_MESSAGE =
    'invalid Modern elsif clause: expected exactly one ASCII space after "elsif"'.freeze
  EXPECT_ELSIF_CONDITION_MESSAGE =
    'invalid Modern elsif condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_ELSIF_CONDITION_SEPARATOR_MESSAGE =
    'invalid Modern elsif clause: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  EXPECT_ELSE_SEPARATOR_MESSAGE =
    'invalid Modern else clause: expected a separator (LF, semicolon, or line comment) after "else"'.freeze
  EXPECT_IF_END_SEPARATOR_MESSAGE =
    'invalid Modern if statement: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  UNEXPECTED_ELSE_MESSAGE = 'unexpected Modern "else": no open if statement'.freeze
  DUPLICATE_ELSE_MESSAGE = 'unexpected Modern "else": if statement already has an else branch'.freeze
  UNEXPECTED_ELSIF_MESSAGE = 'unexpected Modern "elsif": no open if statement'.freeze
  DUPLICATE_ELSIF_MESSAGE = 'unexpected Modern "elsif": if statement already has an else branch'.freeze
  EXPECT_IF_END_MESSAGE = 'unterminated Modern if statement: expected closing "end"'.freeze
  BRANCH_BINDING_MESSAGE = 'Modern if branches do not yet support local bindings'.freeze
  BRANCH_REASSIGNMENT_MESSAGE = 'Modern if branches do not yet support local reassignment'.freeze
  EXPECT_UNLESS_SPACE_MESSAGE =
    'invalid Modern unless statement: expected exactly one ASCII space after "unless"'.freeze
  EXPECT_UNLESS_CONDITION_MESSAGE =
    'invalid Modern unless condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_UNLESS_CONDITION_SEPARATOR_MESSAGE =
    'invalid Modern unless statement: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  EXPECT_UNLESS_END_SEPARATOR_MESSAGE =
    'invalid Modern unless statement: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  DUPLICATE_UNLESS_ELSE_MESSAGE = 'unexpected Modern "else": unless statement already has an else branch'.freeze
  UNSUPPORTED_UNLESS_ELSIF_MESSAGE =
    'unexpected Modern "elsif": unless statement does not support elsif clauses'.freeze
  EXPECT_UNLESS_END_MESSAGE = 'unterminated Modern unless statement: expected closing "end"'.freeze
  UNLESS_BRANCH_BINDING_MESSAGE = 'Modern unless branches do not yet support local bindings'.freeze
  UNLESS_BRANCH_REASSIGNMENT_MESSAGE = 'Modern unless branches do not yet support local reassignment'.freeze
  EXPECT_WHILE_SPACE_MESSAGE =
    'invalid Modern while statement: expected exactly one ASCII space after "while"'.freeze
  EXPECT_WHILE_CONDITION_MESSAGE =
    'invalid Modern while condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_WHILE_CONDITION_SEPARATOR_MESSAGE =
    'invalid Modern while statement: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  EXPECT_WHILE_END_SEPARATOR_MESSAGE =
    'invalid Modern while statement: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  EXPECT_WHILE_END_MESSAGE = 'unterminated Modern while statement: expected closing "end"'.freeze
  WHILE_BODY_BINDING_MESSAGE = 'Modern while bodies do not yet support local bindings'.freeze
  WHILE_BODY_REASSIGNMENT_MESSAGE = 'Modern while bodies do not yet support local reassignment'.freeze
  EXPECT_WHILE_GUARD_REASSIGNMENT_VALUE_MESSAGE =
    'invalid Modern while guard reassignment: expected true or false'.freeze
  EXPECT_CASE_SPACE_MESSAGE =
    'invalid Modern case statement: expected exactly one ASCII space after "case"'.freeze
  EXPECT_CASE_SUBJECT_MESSAGE =
    'invalid Modern case subject: expected an existing Modern literal, earlier local/parameter, or same-document call result'.freeze
  EXPECT_CASE_SUBJECT_SEPARATOR_MESSAGE =
    'invalid Modern case statement: expected a separator (LF, semicolon, or line comment) after subject'.freeze
  EXPECT_CASE_ELSE_SEPARATOR_MESSAGE =
    'invalid Modern case else clause: expected a separator (LF, semicolon, or line comment) after "else"'.freeze
  DUPLICATE_CASE_ELSE_MESSAGE =
    'unexpected Modern "else": case statement already has an else clause'.freeze
  WHEN_AFTER_CASE_ELSE_MESSAGE =
    'unexpected Modern "when": case statement already has an else clause'.freeze
  EXPECT_CASE_CLAUSE_OR_END_MESSAGE =
    'invalid Modern case statement: expected "when", "else", or closing "end" after subject'.freeze
  EXPECT_CASE_END_MESSAGE =
    'unterminated Modern case statement: expected closing "end"'.freeze
  EXPECT_CASE_END_SEPARATOR_MESSAGE =
    'invalid Modern case statement: expected a separator (LF, semicolon, or line comment) after closing "end"'.freeze
  EXPECT_WHEN_SPACE_MESSAGE =
    'invalid Modern when clause: expected exactly one ASCII space after "when"'.freeze
  EXPECT_WHEN_PATTERN_MESSAGE =
    'invalid Modern when pattern: expected one existing Modern literal'.freeze
  EXPECT_WHEN_ALTERNATIVE_MESSAGE =
    'invalid Modern when alternative: expected one existing Modern literal after ","'.freeze
  EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE =
    'invalid Modern when clause: expected a separator (LF, semicolon, or line comment) after pattern'.freeze
  UNEXPECTED_WHEN_COMMA_MESSAGE =
    'unexpected Modern ",": OR-055 does not support comma-separated when alternatives'.freeze
  CASE_CLAUSE_BINDING_MESSAGE = 'Modern case clauses do not yet support local bindings'.freeze
  CASE_CLAUSE_REASSIGNMENT_MESSAGE = 'Modern case clauses do not yet support local reassignment'.freeze
  EXPECT_POSTFIX_SPACE_BEFORE_MESSAGE =
    'invalid Modern postfix guard: expected exactly one ASCII space before "if" or "unless"'.freeze
  EXPECT_POSTFIX_IF_SPACE_MESSAGE =
    'invalid Modern postfix if guard: expected exactly one ASCII space after "if"'.freeze
  EXPECT_POSTFIX_UNLESS_SPACE_MESSAGE =
    'invalid Modern postfix unless guard: expected exactly one ASCII space after "unless"'.freeze
  EXPECT_POSTFIX_IF_CONDITION_MESSAGE =
    'invalid Modern postfix if condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_POSTFIX_UNLESS_CONDITION_MESSAGE =
    'invalid Modern postfix unless condition: expected true, false, or an earlier Boolean parameter/local'.freeze
  EXPECT_POSTFIX_IF_SEPARATOR_MESSAGE =
    'invalid Modern postfix if guard: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  EXPECT_POSTFIX_UNLESS_SEPARATOR_MESSAGE =
    'invalid Modern postfix unless guard: expected a separator (LF, semicolon, or line comment) after condition'.freeze
  CHAINED_POSTFIX_GUARD_MESSAGE =
    'unexpected Modern postfix guard: chained postfix guards are not supported'.freeze
  # This is the checked-in VM Fixnum representation boundary, not a broader
  # decision about the future Dab Numeric contract.
  MAX_LEGACY_FIXNUM_DECIMAL = '9223372036854775807'.freeze

  def initialize(content, source_unit:)
    @source_unit = DabSourceUnit.validate(source_unit)
    unless @source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
      raise DabSourceUnitError.new('Modern bootstrap parser requires DabSyntaxProfile::MODERN')
    end

    @scanner = DabModernBootstrapScanner.new(content, source_unit: @source_unit)
    @callable_name_composer = DabModernCallableNameComposer.new
  end

  def parse
    skip_separators
    return nil if peek_token.kind == :eof

    declarations = []
    until peek_token.kind == :eof
      reject(peek_token, UNEXPECTED_END_MESSAGE) if peek_token.kind == :end
      reject(peek_token, UNEXPECTED_ELSE_MESSAGE) if contextual_else_candidate?
      reject(peek_token, UNEXPECTED_ELSIF_MESSAGE) if contextual_elsif_candidate?
      declarations << parse_declaration
      skip_separators
    end

    DabModernBootstrapDocument.new(declarations)
  end

private

  def parse_declaration
    def_token = expect(:def)
    expect_space_after_def
    callable_name = expect_callable_name
    parameters, return_type, header_tokens = parse_declaration_header
    expect_name_separator
    body_items = parse_body(local_bindings: {})
    end_token = expect(:end)
    final_separator = expect_end_separator

    DabModernBootstrapFunctionDeclaration.new(
      def_token: def_token,
      callable_name: callable_name,
      parameters: parameters,
      return_type: return_type,
      header_tokens: header_tokens,
      body_items: body_items,
      end_token: end_token,
      final_separator: final_separator
    )
  end

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

  def expect_callable_name
    token = next_token
    if token.kind == :identifier
      return compose_callable_name(token)
    end

    if token.kind == :invalid_literal
      reject(token)
    else
      reject(token, EXPECT_CALLABLE_NAME_MESSAGE)
    end
  end

  def next_token
    token_buffer.shift || @scanner.next_token
  end

  def next_value_token
    token_buffer.shift || @scanner.next_token(value_entry: true)
  end

  def peek_token(distance = 0, value_entry: false)
    while token_buffer.length <= distance
      scan_value_entry = value_entry && token_buffer.length == distance
      token_buffer << @scanner.next_token(value_entry: scan_value_entry)
    end
    token_buffer.fetch(distance)
  end

  def peek_value_token(distance = 0)
    peek_token(distance, value_entry: true)
  end

  def compose_callable_name(base_token)
    suffix_token = peek_token
    suffix_token = if @callable_name_composer.adjacent_suffix?(base_token, suffix_token)
                     next_token
                   end
    @callable_name_composer.compose(base_token, suffix_token)
  end

  def parse_declaration_header
    parameters = []
    return_type = nil
    header_tokens = []

    consume_header_whitespace(header_tokens, before: %i[left_parenthesis colon])
    if peek_token.kind == :left_parenthesis
      parameters, parameter_tokens = parse_parameter_clause
      header_tokens.concat(parameter_tokens)
    end

    consume_header_whitespace(header_tokens, before: [:colon])
    if peek_token.kind == :colon
      return_type, return_tokens = parse_return_contract
      header_tokens.concat(return_tokens)
    end

    consume_header_whitespace(header_tokens, before: [])
    [parameters.freeze, return_type, header_tokens.freeze]
  end

  def parse_parameter_clause
    tokens = [expect(:left_parenthesis)]
    tokens.concat(consume_horizontal_whitespace)
    parameters = []
    seen = {}

    if peek_token.kind == :right_parenthesis
      tokens << next_token
      return [parameters.freeze, tokens.freeze]
    end
    reject_invalid_separator(peek_token)
    reject(peek_token, EXPECT_PARAMETER_CLOSE_MESSAGE) if peek_token.kind == :eof

    loop do
      parameter, parameter_tokens = parse_parameter(
        parameters.empty? ? EXPECT_PARAMETER_OR_CLOSE_MESSAGE : EXPECT_PARAMETER_AFTER_COMMA_MESSAGE
      )
      if seen.key?(parameter.name)
        reject(parameter.name_token, %(duplicate Modern parameter "#{parameter.name}"))
      end
      seen[parameter.name] = true
      parameters << parameter
      tokens.concat(parameter_tokens)
      tokens.concat(consume_horizontal_whitespace)

      token = peek_token
      reject_invalid_separator(token)
      case token.kind
      when :right_parenthesis
        tokens << next_token
        return [parameters.freeze, tokens.freeze]
      when :comma
        tokens << next_token
        tokens.concat(consume_horizontal_whitespace)
        reject_invalid_separator(peek_token)
        reject(peek_token, EXPECT_PARAMETER_AFTER_COMMA_MESSAGE) if peek_token.kind == :eof
      when :eof
        reject(token, EXPECT_PARAMETER_CLOSE_MESSAGE)
      else
        reject(token, EXPECT_PARAMETER_SEPARATOR_MESSAGE)
      end
    end
  end

  def parse_parameter(name_message)
    tokens = []
    name_token = next_token
    reject_invalid_separator(name_token)
    reject(name_token, name_message) unless name_token.kind == :identifier
    tokens << name_token
    tokens.concat(consume_horizontal_whitespace)

    colon_token = next_token
    reject_invalid_separator(colon_token)
    reject(colon_token, EXPECT_PARAMETER_COLON_MESSAGE) unless colon_token.kind == :colon
    tokens << colon_token
    tokens.concat(consume_horizontal_whitespace)

    type_name = parse_type_name(EXPECT_PARAMETER_TYPE_MESSAGE)
    tokens << type_name.token
    [
      DabModernBootstrapParameter.new(
        name_token: name_token,
        colon_token: colon_token,
        type_name: type_name
      ),
      tokens.freeze,
    ]
  end

  def parse_return_contract
    tokens = [expect(:colon)]
    tokens.concat(consume_horizontal_whitespace)
    type_name = parse_type_name(EXPECT_RETURN_TYPE_MESSAGE)
    tokens << type_name.token
    [type_name, tokens.freeze]
  end

  def parse_type_name(expectation_message)
    token = next_token
    reject_invalid_separator(token)
    reject(token, expectation_message) unless token.kind == :identifier
    unless SUPPORTED_TYPE_NAMES.include?(token.text)
      reject(
        token,
        %(unknown Modern type "#{token.text}"; supported types are ) \
        "#{SUPPORTED_TYPE_NAMES[0...-1].join(', ')}, and #{SUPPORTED_TYPE_NAMES.fetch(-1)}"
      )
    end
    DabModernBootstrapTypeName.new(token)
  end

  def consume_header_whitespace(tokens, before:)
    return unless horizontal_whitespace?(peek_token)

    following = token_after_horizontal_whitespace
    accepted_after = before + SEPARATOR_KINDS + %i[carriage_return eof]
    tokens.concat(consume_horizontal_whitespace) if accepted_after.include?(following.kind)
  end

  def consume_horizontal_whitespace
    tokens = []
    tokens << next_token while horizontal_whitespace?(peek_token)
    tokens
  end

  def consume_value_entry_whitespace
    tokens = []
    tokens << next_token while horizontal_whitespace?(peek_value_token)
    tokens
  end

  def horizontal_whitespace?(token)
    HORIZONTAL_WHITESPACE_KINDS.include?(token.kind)
  end

  def token_after_horizontal_whitespace
    distance = 0
    distance += 1 while horizontal_whitespace?(peek_token(distance))
    peek_token(distance)
  end

  def expect_name_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    if token.kind == :space && implemented_shell_token_after_spaces?
      reject(token, EXPECT_NAME_SEPARATOR_MESSAGE)
    end
    if (%i[eof end] + VALUE_KINDS).include?(token.kind)
      reject(token, EXPECT_NAME_SEPARATOR_MESSAGE)
    end

    reject(token)
  end

  def expect_literal_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
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
    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_END_SEPARATOR_MESSAGE) unless separator?(token)
    token
  end

  def parse_body(
    local_bindings:,
    branch_rejection_context: nil,
    open_structure: nil,
    stop_at_conditional_clause: false,
    stop_at_case_clause: false
  )
    items = []
    loop do
      skip_body_separators
      break if peek_token.kind == :end
      break if stop_at_conditional_clause &&
               (contextual_elsif_candidate? || contextual_else_candidate?)
      break if stop_at_case_clause &&
               (contextual_case_clause_candidate?('when') ||
                contextual_case_clause_candidate?('else'))

      if contextual_elsif_candidate?
        message = if open_structure == :unless
                    UNSUPPORTED_UNLESS_ELSIF_MESSAGE
                  elsif open_structure == :if
                    DUPLICATE_ELSIF_MESSAGE
                  else
                    UNEXPECTED_ELSIF_MESSAGE
                  end
        reject(peek_token, message)
      end

      if contextual_else_candidate?
        message = if open_structure == :unless
                    DUPLICATE_UNLESS_ELSE_MESSAGE
                  elsif open_structure == :if
                    DUPLICATE_ELSE_MESSAGE
                  else
                    UNEXPECTED_ELSE_MESSAGE
                  end
        reject(peek_token, message)
      end

      if peek_token.kind == :eof
        message = case open_structure
                  when :unless then EXPECT_UNLESS_END_MESSAGE
                  when :if then EXPECT_IF_END_MESSAGE
                  when :while then EXPECT_WHILE_END_MESSAGE
                  when :case then EXPECT_CASE_END_MESSAGE
                  else EXPECT_END_MESSAGE
                  end
        reject(peek_token, message)
      end

      if contextual_while_candidate?(local_bindings)
        items << parse_while_statement(local_bindings, branch_rejection_context)
        next
      end

      if contextual_if_candidate?
        items << parse_if_statement(local_bindings, branch_rejection_context)
        next
      end

      if contextual_unless_candidate?
        items << parse_unless_statement(local_bindings, branch_rejection_context)
        next
      end

      if peek_token.kind == :return
        items << parse_return
        next
      end

      if literal_member_start?
        item = parse_literal_member(consume_separator: false)
        items << finish_guardable_item(item, :member_call)
        next
      end

      if local_reassignment_start?(local_bindings) ||
         (branch_rejection_context == :while && reassignment_syntax_start?) ||
         ((peek_token.text == 'break' || peek_token.text == 'next') && reassignment_syntax_start?)
        if branch_rejection_context && !%i[while case].include?(branch_rejection_context)
          reject_branch_reassignment(peek_token, branch_rejection_context)
        end
        items << parse_local_reassignment(
          local_bindings[peek_token.text],
          allow_while_guard_form: branch_rejection_context == :while
        )
        next
      end

      if contextual_case_candidate?
        items << parse_case_statement(local_bindings)
        next
      end

      if direct_call_start?
        item = parse_direct_call
        items << finish_guardable_item(item, :call)
        next
      end

      if contextual_let_start?
        if branch_rejection_context && !%i[while case].include?(branch_rejection_context)
          reject_branch_binding(peek_token, branch_rejection_context)
        end
        binding = parse_local_binding
        items << binding
        local_bindings[binding.name] ||= binding
        next
      end

      if contextual_var_start?(local_bindings)
        if branch_rejection_context && !%i[while case].include?(branch_rejection_context)
          reject_branch_binding(peek_token, branch_rejection_context)
        end
        binding = parse_mutable_local_binding
        items << binding
        local_bindings[binding.name] = binding
        next
      end

      if contextual_break_candidate?
        break_item = DabModernBootstrapBreak.new(next_token)
        items << finish_guardable_item(break_item, :break)
        next
      end

      if contextual_next_candidate?
        next_item = DabModernBootstrapNext.new(next_token)
        items << finish_guardable_item(next_item, :next)
        next
      end

      token = next_token
      reject_value_token(token)
      unless executable_value?(token)
        reject(token)
      end
      if token.kind == :integer && integer_overflow?(token.text)
        reject(
          token,
          'Modern integer literal is outside supported range 0..9223372036854775807'
        )
      end
      items << token
      items[-1] = finish_guardable_item(token, :literal)
    end
    items.freeze
  end

  def parse_if_statement(local_bindings, enclosing_rejection_context = nil)
    if_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_IF_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_token, EXPECT_IF_SPACE_MESSAGE) if peek_token.kind == :space

    condition_token, condition = parse_if_condition(EXPECT_IF_CONDITION_MESSAGE)
    condition_separator = expect_if_condition_separator(
      condition_token,
      EXPECT_IF_CONDITION_SEPARATOR_MESSAGE,
      EXPECT_IF_CONDITION_MESSAGE
    )
    rejection_context = nested_rejection_context(enclosing_rejection_context, :if)
    if_true = parse_body(
      local_bindings: local_bindings,
      branch_rejection_context: rejection_context,
      open_structure: :if,
      stop_at_conditional_clause: true
    )

    elsif_clauses = []
    elsif_clauses << parse_elsif_clause(local_bindings, rejection_context) while contextual_elsif_candidate?

    else_token = nil
    else_separator = nil
    if_false = nil
    if contextual_else_candidate?
      else_token = next_token
      else_separator = expect_if_separator(EXPECT_ELSE_SEPARATOR_MESSAGE)
      if_false = parse_body(
        local_bindings: local_bindings,
        branch_rejection_context: rejection_context,
        open_structure: :if
      )
    end

    reject(peek_token, EXPECT_IF_END_MESSAGE) if peek_token.kind == :eof
    end_token = expect(:end)
    final_separator = expect_if_separator(EXPECT_IF_END_SEPARATOR_MESSAGE)
    DabModernBootstrapIfStatement.new(
      if_token: if_token,
      space_token: space_token,
      condition: condition,
      condition_separator: condition_separator,
      if_true: if_true,
      elsif_clauses: elsif_clauses,
      else_token: else_token,
      else_separator: else_separator,
      if_false: if_false,
      end_token: end_token,
      final_separator: final_separator
    )
  end

  def parse_unless_statement(local_bindings, enclosing_rejection_context = nil)
    unless_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_UNLESS_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_token, EXPECT_UNLESS_SPACE_MESSAGE) if peek_token.kind == :space

    condition_token, condition = parse_if_condition(EXPECT_UNLESS_CONDITION_MESSAGE)
    condition_separator = expect_if_condition_separator(
      condition_token,
      EXPECT_UNLESS_CONDITION_SEPARATOR_MESSAGE,
      EXPECT_UNLESS_CONDITION_MESSAGE
    )
    rejection_context = nested_rejection_context(enclosing_rejection_context, :unless)
    unless_body = parse_body(
      local_bindings: local_bindings,
      branch_rejection_context: rejection_context,
      open_structure: :unless,
      stop_at_conditional_clause: true
    )

    reject(peek_token, UNSUPPORTED_UNLESS_ELSIF_MESSAGE) if contextual_elsif_candidate?

    else_token = nil
    else_separator = nil
    else_body = nil
    if contextual_else_candidate?
      else_token = next_token
      else_separator = expect_if_separator(EXPECT_ELSE_SEPARATOR_MESSAGE)
      else_body = parse_body(
        local_bindings: local_bindings,
        branch_rejection_context: rejection_context,
        open_structure: :unless
      )
    end

    reject(peek_token, EXPECT_UNLESS_END_MESSAGE) if peek_token.kind == :eof
    end_token = expect(:end)
    final_separator = expect_if_separator(EXPECT_UNLESS_END_SEPARATOR_MESSAGE)
    DabModernBootstrapUnlessStatement.new(
      unless_token: unless_token,
      space_token: space_token,
      condition: condition,
      condition_separator: condition_separator,
      unless_body: unless_body,
      else_token: else_token,
      else_separator: else_separator,
      else_body: else_body,
      end_token: end_token,
      final_separator: final_separator
    )
  end

  def parse_elsif_clause(local_bindings, rejection_context)
    elsif_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_ELSIF_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_token, EXPECT_ELSIF_SPACE_MESSAGE) if peek_token.kind == :space

    condition_token, condition = parse_if_condition(EXPECT_ELSIF_CONDITION_MESSAGE)
    condition_separator = expect_if_condition_separator(
      condition_token,
      EXPECT_ELSIF_CONDITION_SEPARATOR_MESSAGE,
      EXPECT_ELSIF_CONDITION_MESSAGE
    )
    body = parse_body(
      local_bindings: local_bindings,
      branch_rejection_context: rejection_context,
      open_structure: :if,
      stop_at_conditional_clause: true
    )
    DabModernBootstrapElsifClause.new(
      elsif_token: elsif_token,
      space_token: space_token,
      condition: condition,
      condition_separator: condition_separator,
      body: body,
      end_location: peek_token.source_span.start_location
    )
  end

  def parse_while_statement(local_bindings, enclosing_rejection_context = nil)
    while_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_WHILE_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_token, EXPECT_WHILE_SPACE_MESSAGE) if peek_token.kind == :space

    condition_token, condition = parse_if_condition(EXPECT_WHILE_CONDITION_MESSAGE)
    condition_separator = expect_if_condition_separator(
      condition_token,
      EXPECT_WHILE_CONDITION_SEPARATOR_MESSAGE,
      EXPECT_WHILE_CONDITION_MESSAGE
    )
    rejection_context = nested_rejection_context(enclosing_rejection_context, :while)
    loop_items = parse_body(
      local_bindings: local_bindings.dup,
      branch_rejection_context: rejection_context,
      open_structure: :while
    )

    reject(peek_token, EXPECT_WHILE_END_MESSAGE) if peek_token.kind == :eof
    end_token = expect(:end)
    final_separator = expect_if_separator(EXPECT_WHILE_END_SEPARATOR_MESSAGE)
    DabModernBootstrapWhileStatement.new(
      while_token: while_token,
      space_token: space_token,
      condition: condition,
      condition_separator: condition_separator,
      loop_items: loop_items,
      end_token: end_token,
      final_separator: final_separator
    )
  end

  def parse_case_statement(local_bindings)
    case_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_CASE_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_token, EXPECT_CASE_SPACE_MESSAGE) if peek_token.kind == :space

    subject = parse_case_subject
    subject_separator = expect_case_separator(EXPECT_CASE_SUBJECT_SEPARATOR_MESSAGE)
    skip_body_separators

    when_clauses = []
    while contextual_case_clause_candidate?('when')
      when_clauses << parse_when_clause(local_bindings)
      skip_body_separators
    end

    else_clause = nil
    if contextual_case_clause_candidate?('else')
      else_token = next_token
      else_separator = expect_case_separator(EXPECT_CASE_ELSE_SEPARATOR_MESSAGE)
      else_body = parse_body(
        local_bindings: local_bindings.dup,
        branch_rejection_context: :case,
        open_structure: :case,
        stop_at_case_clause: true
      )
      else_clause = DabModernBootstrapCaseElseClause.new(
        else_token: else_token,
        separator: else_separator,
        body: else_body,
        end_location: peek_token.source_span.start_location
      )
      skip_body_separators
      reject(peek_token, WHEN_AFTER_CASE_ELSE_MESSAGE) if contextual_case_clause_candidate?('when')
      reject(peek_token, DUPLICATE_CASE_ELSE_MESSAGE) if contextual_case_clause_candidate?('else')
    end

    reject(peek_token, EXPECT_CASE_END_MESSAGE) if peek_token.kind == :eof
    reject(peek_token, EXPECT_CASE_CLAUSE_OR_END_MESSAGE) unless peek_token.kind == :end

    end_token = next_token
    final_separator = expect_case_separator(EXPECT_CASE_END_SEPARATOR_MESSAGE)
    DabModernBootstrapCaseStatement.new(
      case_token: case_token,
      space_token: space_token,
      subject: subject,
      subject_separator: subject_separator,
      when_clauses: when_clauses,
      else_clause: else_clause,
      end_token: end_token,
      final_separator: final_separator
    )
  end

  def parse_when_clause(local_bindings)
    when_token = next_token
    space_token = next_token
    reject(space_token, EXPECT_WHEN_SPACE_MESSAGE) unless space_token.kind == :space
    reject(peek_value_token, EXPECT_WHEN_SPACE_MESSAGE) if horizontal_whitespace?(peek_value_token)

    pattern = parse_when_pattern
    patterns = [pattern]
    pattern_tokens = [pattern]
    loop do
      whitespace = consume_horizontal_whitespace
      unless peek_token.kind == :comma
        unless whitespace.empty?
          reject_invalid_separator(peek_token)
          reject(whitespace.fetch(0), EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE)
        end
        break
      end

      pattern_tokens.concat(whitespace)
      pattern_tokens << next_token
      pattern_tokens.concat(consume_value_entry_whitespace)
      alternative = parse_when_pattern(EXPECT_WHEN_ALTERNATIVE_MESSAGE)
      patterns << alternative
      pattern_tokens << alternative
    end
    pattern_separator = expect_when_separator
    body = parse_body(
      local_bindings: local_bindings.dup,
      branch_rejection_context: :case,
      open_structure: :case,
      stop_at_case_clause: true
    )
    DabModernBootstrapWhenClause.new(
      when_token: when_token,
      space_token: space_token,
      patterns: patterns,
      pattern_tokens: pattern_tokens,
      pattern_separator: pattern_separator,
      body: body,
      end_location: peek_token.source_span.start_location
    )
  end

  def parse_when_pattern(expectation = EXPECT_WHEN_PATTERN_MESSAGE)
    token = peek_value_token
    reject_invalid_separator(token)
    reject(token, token.diagnostic_message) if token.diagnostic_message
    reject(token, expectation) if token.kind == :eof || token.kind == :comma ||
                                  token.kind == :end || separator?(token)

    if direct_call_start?
      return reject_when_pattern(parse_direct_call, expectation)
    end

    if literal_member_start?
      return reject_when_pattern(parse_literal_member(argument: true), expectation)
    end

    if token.kind == :regex_literal || VALUE_KINDS.include?(token.kind)
      return next_token.tap { |literal| reject_integer_overflow(literal) }
    end

    reject_when_pattern_form(expectation)
  end

  def reject_when_pattern(pattern, expectation)
    raise DabModernBootstrapParseError.new(
      expectation,
      source_span: pattern.source_span
    )
  end

  def reject_when_pattern_form(expectation)
    first_token = next_token
    last_token = first_token
    last_token = next_token until separator?(peek_token) ||
                                  %i[eof end carriage_return].include?(peek_token.kind)
    source_span = DabSourceSpan.new(
      start_location: first_token.source_span.start_location,
      end_location: last_token.source_span.end_location
    )
    raise DabModernBootstrapParseError.new(expectation, source_span: source_span)
  end

  def expect_when_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject(token, UNEXPECTED_WHEN_COMMA_MESSAGE) if token.kind == :comma

    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE)
  end

  def parse_case_subject
    token = peek_value_token
    reject_invalid_separator(token)
    reject_value_token(token)

    if direct_call_start?
      return parse_direct_call(allow_call_result_arguments: false)
    end

    if literal_member_start?
      member = parse_literal_member(argument: true)
      return reject_case_subject(EXPECT_CASE_SUBJECT_MESSAGE, member)
    end

    if executable_value?(token)
      return next_token.tap { |literal| reject_integer_overflow(literal) }
    end

    if token.kind == :identifier
      return reject_case_subject_form if adjacent_member_tail?(token)

      return DabModernBootstrapLocalReference.new(next_token)
    end

    reject_case_subject_form
  end

  def reject_case_subject(message, subject)
    raise DabModernBootstrapParseError.new(message, source_span: subject.source_span)
  end

  def reject_case_subject_form
    first_token = next_token
    last_token = first_token
    last_token = next_token until separator?(peek_token) ||
                                  %i[eof end carriage_return].include?(peek_token.kind)
    source_span = DabSourceSpan.new(
      start_location: first_token.source_span.start_location,
      end_location: last_token.source_span.end_location
    )
    raise DabModernBootstrapParseError.new(EXPECT_CASE_SUBJECT_MESSAGE, source_span: source_span)
  end

  def adjacent_member_tail?(token)
    dot = peek_token(1)
    dot.kind == :dot && token.source_span.end_offset == dot.source_span.start_offset
  end

  def expect_case_separator(message)
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, message)
  end

  def parse_if_condition(expectation_message)
    condition_token = next_token
    reject_invalid_separator(condition_token)
    condition = if %i[boolean_true boolean_false].include?(condition_token.kind)
                  condition_token
                elsif condition_token.kind == :identifier
                  DabModernBootstrapLocalReference.new(condition_token)
                else
                  reject_if_condition_form(condition_token, expectation_message)
                end
    [condition_token, condition]
  end

  def expect_if_separator(message)
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, message)
  end

  def expect_if_condition_separator(condition_token, separator_message, condition_message)
    token = peek_token
    reject_invalid_separator(token)
    return next_token if separator?(token)

    if horizontal_whitespace?(token)
      return expect_if_separator(separator_message)
    end

    reject_if_condition_form(condition_token, condition_message)
  end

  def reject_if_condition_form(first_token, expectation_message)
    last_token = first_token
    last_token = next_token until separator?(peek_token) ||
                                  %i[eof end carriage_return].include?(peek_token.kind)
    source_span = DabSourceSpan.new(
      start_location: first_token.source_span.start_location,
      end_location: last_token.source_span.end_location
    )
    raise DabModernBootstrapParseError.new(expectation_message, source_span: source_span)
  end

  def contextual_if_candidate?
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'if'

    peek_token(1).kind == :space || !direct_call_start?
  end

  def contextual_unless_candidate?
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'unless'

    !direct_call_start?
  end

  def contextual_while_candidate?(_local_bindings)
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'while'
    return false if direct_call_start?

    distance = distance_after_horizontal_whitespace(1)
    peek_token(distance).kind != :equal
  end

  def contextual_case_candidate?
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'case'
    return false if direct_call_start_at?(0, value_entry_after_whitespace: true)

    !@callable_name_composer.adjacent_suffix?(token, peek_token(1))
  end

  def contextual_case_clause_candidate?(name)
    token = peek_token
    return false unless token.kind == :identifier && token.text == name

    value_entry = name == 'when'
    return false if direct_call_start_at?(0, value_entry_after_whitespace: value_entry)
    return false if @callable_name_composer.adjacent_suffix?(token, peek_token(1))

    distance = distance_after_horizontal_whitespace(1, value_entry: value_entry)
    peek_token(distance, value_entry: value_entry).kind != :equal
  end

  def nested_rejection_context(enclosing_context, default_context)
    return :case if enclosing_context == :case
    return :while if enclosing_context == :while

    default_context
  end

  def contextual_break_candidate?
    token = peek_token
    token.kind == :identifier && token.text == 'break'
  end

  def contextual_next_candidate?
    token = peek_token
    token.kind == :identifier && token.text == 'next'
  end

  def reject_branch_binding(token, context)
    message = case context
              when :unless then UNLESS_BRANCH_BINDING_MESSAGE
              when :while then WHILE_BODY_BINDING_MESSAGE
              else BRANCH_BINDING_MESSAGE
              end
    reject(token, message)
  end

  def reject_branch_reassignment(token, context)
    message = case context
              when :unless then UNLESS_BRANCH_REASSIGNMENT_MESSAGE
              when :while then WHILE_BODY_REASSIGNMENT_MESSAGE
              else BRANCH_REASSIGNMENT_MESSAGE
              end
    reject(token, message)
  end

  def contextual_else_candidate?
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'else'
    return false if direct_call_start?
    return false if @callable_name_composer.adjacent_suffix?(token, peek_token(1))

    !reassignment_syntax_start?
  end

  def contextual_elsif_candidate?
    token = peek_token
    token.kind == :identifier && token.text == 'elsif' && !direct_call_start?
  end

  def direct_call_start?
    direct_call_start_at?(0)
  end

  def direct_call_start_at?(start_distance, value_entry: false, value_entry_after_whitespace: false)
    base_token = peek_token(start_distance, value_entry: value_entry)
    return false unless base_token.kind == :identifier

    distance = start_distance + 1
    suffix_token = peek_token(distance)
    distance += 1 if @callable_name_composer.adjacent_suffix?(base_token, suffix_token)
    distance += 1 while horizontal_whitespace?(
      peek_token(distance, value_entry: value_entry_after_whitespace)
    )
    peek_token(distance, value_entry: value_entry_after_whitespace).kind == :left_parenthesis
  end

  def parse_return
    keyword_token = expect(:return)
    token = peek_token
    reject_invalid_separator(token)
    if separator?(token)
      return finish_guardable_item(
        DabModernBootstrapBareReturn.new(keyword_token),
        :bare_return
      )
    end

    if token.kind == :space
      bare_return = DabModernBootstrapBareReturn.new(keyword_token)
      if !direct_call_start_at?(1, value_entry: true) &&
         (postfix_guard_candidate? || malformed_postfix_guard_prefix?)
        return finish_guardable_item(bare_return, :bare_return)
      end

      space_token = next_token
      return parse_value_return(keyword_token, space_token) if value_return_start?

      reject_invalid_separator_after_spaces(space_token)
      reject(space_token, EXPECT_BARE_RETURN_SEPARATOR_MESSAGE)
    end

    token = next_token
    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_BARE_RETURN_SEPARATOR_MESSAGE)
  end

  def value_return_start?
    token = peek_value_token
    token.kind == :identifier || executable_value?(token) ||
      literal_member_start? || !token.diagnostic_message.nil?
  end

  def parse_value_return(keyword_token, space_token)
    token = peek_value_token
    reject_invalid_separator(token)
    reject(token) if horizontal_whitespace?(token)
    reject_value_token(token)

    value = if direct_call_start?
              parse_direct_call(allow_call_result_arguments: false)
            elsif literal_member_start?
              parse_literal_member(argument: true)
            elsif executable_value?(token)
              next_token.tap { |literal| reject_integer_overflow(literal) }
            elsif token.kind == :identifier && bare_return_local_reference?
              DabModernBootstrapLocalReference.new(next_token)
            else
              reject(token)
            end
    value_return = DabModernBootstrapValueReturn.new(
      keyword_token: keyword_token,
      space_token: space_token,
      value: value,
      separator_token: nil
    )
    finish_guardable_value_return(value_return)
  end

  def bare_return_local_reference?
    distance = 1
    distance += 1 while horizontal_whitespace?(peek_token(distance))
    separator?(peek_token(distance)) || %i[eof end carriage_return].include?(peek_token(distance).kind)
  end

  def expect_returned_value_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_VALUE_RETURN_SEPARATOR_MESSAGE)
  end

  def finish_guardable_value_return(value_return)
    return parse_postfix_guard(value_return) if postfix_guard_candidate?

    spacing_error = postfix_before_spacing_error_token
    reject(spacing_error, EXPECT_POSTFIX_SPACE_BEFORE_MESSAGE) if spacing_error

    separator_token = expect_returned_value_separator
    DabModernBootstrapValueReturn.new(
      keyword_token: value_return.keyword_token,
      space_token: value_return.source_tokens.fetch(1),
      value: value_return.value,
      separator_token: separator_token
    )
  end

  def contextual_let_start?
    token = peek_token
    token.kind == :identifier && token.text == 'let'
  end

  def contextual_var_start?(local_bindings)
    token = peek_token
    return false unless token.kind == :identifier && token.text == 'var'
    return true unless local_bindings.key?('var')

    token_after_name_horizontal_whitespace.kind != :equal
  end

  def local_reassignment_start?(local_bindings)
    local_bindings.key?(peek_token.text) && reassignment_syntax_start?
  end

  def reassignment_syntax_start?
    name_token = peek_token
    return false unless name_token.kind == :identifier

    equal_distance = distance_after_horizontal_whitespace(1)
    return false unless peek_token(equal_distance).kind == :equal

    value_distance = distance_after_horizontal_whitespace(equal_distance + 1, value_entry: true)
    value_token = peek_value_token(value_distance)
    return true unless value_token.kind == :equal

    peek_token(equal_distance).source_span.end_offset != value_token.source_span.start_offset
  end

  def token_after_name_horizontal_whitespace
    peek_token(distance_after_horizontal_whitespace(1))
  end

  def distance_after_horizontal_whitespace(distance, value_entry: false)
    distance += 1 while horizontal_whitespace?(peek_token(distance, value_entry: value_entry))
    distance
  end

  def parse_local_binding
    source_tokens = []
    let_token = next_token
    source_tokens << let_token

    space_token = next_token
    reject(space_token, EXPECT_LET_SPACE_MESSAGE) unless space_token.kind == :space
    source_tokens << space_token

    name_token = next_token
    reject_invalid_separator(name_token)
    reject(name_token, EXPECT_LET_NAME_MESSAGE) unless name_token.kind == :identifier
    source_tokens << name_token
    source_tokens.concat(consume_horizontal_whitespace)

    type_name = parse_local_type_annotation(source_tokens)

    equal_token = next_token
    reject_invalid_separator(equal_token)
    unless equal_token.kind == :equal
      reject(equal_token, EXPECT_TYPED_LET_EQUAL_MESSAGE) if type_name
      if (%i[eof end line_feed semicolon line_comment] + VALUE_KINDS).include?(equal_token.kind)
        reject(equal_token, EXPECT_LET_EQUAL_MESSAGE)
      end
      reject(equal_token)
    end
    source_tokens << equal_token
    source_tokens.concat(consume_value_entry_whitespace)

    initializer_token = next_value_token
    reject_invalid_separator(initializer_token)
    reject_value_token(initializer_token)
    unless executable_value?(initializer_token)
      if %i[eof end line_feed semicolon line_comment].include?(initializer_token.kind)
        reject(initializer_token, EXPECT_LET_INITIALIZER_MESSAGE)
      end
      reject(initializer_token)
    end
    reject_integer_overflow(initializer_token)
    source_tokens << initializer_token

    expect_let_body_separator
    DabModernBootstrapLocalBinding.new(
      let_token: let_token,
      name_token: name_token,
      type_name: type_name,
      equal_token: equal_token,
      initializer_token: initializer_token,
      source_tokens: source_tokens
    )
  end

  def parse_mutable_local_binding
    source_tokens = []
    var_token = next_token
    source_tokens << var_token

    space_token = next_token
    reject(space_token, EXPECT_VAR_SPACE_MESSAGE) unless space_token.kind == :space
    source_tokens << space_token

    name_token = next_token
    reject_invalid_separator(name_token)
    reject(name_token, EXPECT_VAR_NAME_MESSAGE) unless name_token.kind == :identifier
    source_tokens << name_token
    source_tokens.concat(consume_horizontal_whitespace)

    type_name = parse_local_type_annotation(source_tokens)

    equal_token = next_token
    reject_invalid_separator(equal_token)
    unless equal_token.kind == :equal
      reject(equal_token, EXPECT_TYPED_VAR_EQUAL_MESSAGE) if type_name
      if (%i[eof end line_feed semicolon line_comment] + VALUE_KINDS).include?(equal_token.kind)
        reject(equal_token, EXPECT_VAR_EQUAL_MESSAGE)
      end
      reject(equal_token)
    end
    source_tokens << equal_token
    source_tokens.concat(consume_value_entry_whitespace)

    initializer_token = next_value_token
    reject_invalid_separator(initializer_token)
    reject_value_token(initializer_token)
    unless executable_value?(initializer_token)
      if %i[eof end line_feed semicolon line_comment].include?(initializer_token.kind)
        reject(initializer_token, EXPECT_VAR_INITIALIZER_MESSAGE)
      end
      reject(initializer_token)
    end
    reject_integer_overflow(initializer_token)
    source_tokens << initializer_token

    expect_local_body_separator(EXPECT_VAR_SEPARATOR_MESSAGE)
    DabModernBootstrapMutableLocalBinding.new(
      var_token: var_token,
      name_token: name_token,
      type_name: type_name,
      equal_token: equal_token,
      initializer_token: initializer_token,
      source_tokens: source_tokens
    )
  end

  def parse_local_type_annotation(source_tokens)
    return unless peek_token.kind == :colon

    source_tokens << next_token
    source_tokens.concat(consume_horizontal_whitespace)
    type_name = parse_type_name(EXPECT_LOCAL_TYPE_MESSAGE)
    source_tokens << type_name.token
    source_tokens.concat(consume_horizontal_whitespace)
    type_name
  end

  def parse_local_reassignment(binding, allow_while_guard_form: false)
    source_tokens = []
    name_token = next_token
    source_tokens << name_token
    source_tokens.concat(consume_horizontal_whitespace)

    equal_token = expect(:equal)
    source_tokens << equal_token
    source_tokens.concat(consume_value_entry_whitespace)

    value_token = next_value_token
    reject_invalid_separator(value_token)
    reject_value_token(value_token)
    if allow_while_guard_form && regex_literal?(value_token)
      reject(value_token, EXPECT_WHILE_GUARD_REASSIGNMENT_VALUE_MESSAGE)
    end
    if allow_while_guard_form && %i[eof end line_feed semicolon line_comment].include?(value_token.kind)
      reject(value_token, EXPECT_REASSIGNMENT_VALUE_MESSAGE)
    end
    unless executable_value?(value_token) || allow_while_guard_form
      if %i[eof end line_feed semicolon line_comment].include?(value_token.kind)
        reject(value_token, EXPECT_REASSIGNMENT_VALUE_MESSAGE)
      end
      reject(value_token)
    end
    reject_integer_overflow(value_token) if executable_value?(value_token)
    source_tokens << value_token

    if allow_while_guard_form && while_guard_value_form_continues?
      value_tokens = [value_token]
      value_tokens << next_token until separator?(peek_token) ||
                                       %i[eof end carriage_return].include?(peek_token.kind)
      source_tokens.concat(value_tokens.drop(1))
      value_token = DabModernBootstrapWhileGuardValueForm.new(value_tokens)
    end

    expect_local_body_separator(EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE)
    DabModernBootstrapLocalReassignment.new(
      name_token: name_token,
      type_name: binding&.type_name,
      equal_token: equal_token,
      value_token: value_token,
      source_tokens: source_tokens
    )
  end

  def while_guard_value_form_continues?
    return false if separator?(peek_token) || %i[eof end carriage_return].include?(peek_token.kind)

    if horizontal_whitespace?(peek_token)
      after_whitespace = peek_token(distance_after_horizontal_whitespace(0))
      return false if separator?(after_whitespace) ||
                      %i[eof end carriage_return].include?(after_whitespace.kind)
    end

    true
  end

  def literal_member_start?
    receiver = peek_token
    dot = peek_token(1)
    executable_literal?(receiver) && dot.kind == :dot &&
      receiver.source_span.end_offset == dot.source_span.start_offset
  end

  def parse_literal_member(argument: false, consume_separator: true)
    source_tokens = []
    receiver_token = next_token
    reject_integer_overflow(receiver_token)
    source_tokens << receiver_token
    dot_token = expect(:dot)
    source_tokens << dot_token

    base_token = next_token
    reject(base_token, EXPECT_DOT_CALLABLE_NAME_MESSAGE) unless base_token.kind == :identifier
    source_tokens << base_token
    callable_name = compose_callable_name(base_token)
    source_tokens << callable_name.suffix_token if callable_name.suffix_token

    if argument && nested_property_tail?
      return build_literal_member_call(
        receiver_token,
        dot_token,
        callable_name,
        [],
        source_tokens
      )
    end

    reject_invalid_separator(peek_token)
    if separator?(peek_token)
      next_token if consume_separator
      return build_literal_member_call(
        receiver_token,
        dot_token,
        callable_name,
        [],
        source_tokens
      )
    end

    if !argument && !consume_separator &&
       (postfix_guard_candidate? || malformed_postfix_guard_prefix?)
      return build_literal_member_call(
        receiver_token,
        dot_token,
        callable_name,
        [],
        source_tokens
      )
    end

    if horizontal_whitespace?(peek_token)
      reject(peek_token, EXPECT_MEMBER_TAIL_MESSAGE) unless token_after_horizontal_whitespace.kind == :left_parenthesis

      source_tokens.concat(consume_horizontal_whitespace)
    end

    reject(peek_token, EXPECT_MEMBER_TAIL_MESSAGE) unless peek_token.kind == :left_parenthesis
    arguments, closing_parenthesis = parse_call_arguments(
      source_tokens,
      allow_member_results: false,
      allow_local_references: false,
      allow_interpolated_strings: false
    )
    member_call = build_literal_member_call(
      receiver_token,
      dot_token,
      callable_name,
      arguments,
      source_tokens,
      closing_parenthesis: closing_parenthesis
    )
    expect_member_call_body_separator if !argument && consume_separator
    member_call
  end

  def parse_direct_call(allow_call_result_arguments: true)
    source_tokens = []
    base_token = next_token
    source_tokens << base_token
    callable_name = compose_callable_name(base_token)
    source_tokens << callable_name.suffix_token if callable_name.suffix_token
    source_tokens.concat(consume_horizontal_whitespace)
    arguments, closing_parenthesis = parse_call_arguments(
      source_tokens,
      allow_member_results: true,
      allow_local_references: true,
      allow_call_results: allow_call_result_arguments,
      allow_interpolated_strings: true
    )
    build_direct_call(callable_name, arguments, source_tokens, closing_parenthesis)
  end

  def parse_call_arguments(
    source_tokens,
    allow_member_results:,
    allow_local_references:,
    allow_interpolated_strings:,
    allow_call_results: false
  )
    source_tokens << expect(:left_parenthesis)
    source_tokens.concat(consume_value_entry_whitespace)
    arguments = []

    if peek_value_token.kind == :right_parenthesis
      closing_parenthesis = next_token
      source_tokens << closing_parenthesis
      return [arguments.freeze, closing_parenthesis]
    end
    reject(peek_token, EXPECT_CALL_CLOSE_MESSAGE) if peek_token.kind == :eof

    expectation = EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    loop do
      argument = parse_call_argument(
        expectation,
        allow_member_results: allow_member_results,
        allow_local_references: allow_local_references,
        allow_call_results: allow_call_results,
        allow_interpolated_strings: allow_interpolated_strings
      )
      arguments << argument
      source_tokens.concat(argument_source_tokens(argument))
      source_tokens.concat(consume_horizontal_whitespace)
      token = peek_token
      reject_invalid_separator(token)

      case token.kind
      when :right_parenthesis
        closing_parenthesis = next_token
        source_tokens << closing_parenthesis
        return [arguments.freeze, closing_parenthesis]
      when :comma
        source_tokens << next_token
        source_tokens.concat(consume_value_entry_whitespace)
        expectation = EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE
      when :eof
        reject(token, EXPECT_CALL_CLOSE_MESSAGE)
      else
        reject(token, EXPECT_CALL_ARGUMENT_SEPARATOR_MESSAGE)
      end
    end
  end

  def parse_call_argument(
    expectation,
    allow_member_results:,
    allow_local_references:,
    allow_call_results:,
    allow_interpolated_strings:
  )
    token = peek_value_token
    reject_invalid_separator(token)
    if token.kind == :eof
      reject(token, expectation == EXPECT_CALL_ARGUMENT_AFTER_COMMA_MESSAGE ? expectation : EXPECT_CALL_CLOSE_MESSAGE)
    end
    reject_value_token(token)
    if allow_member_results && literal_member_start?
      return parse_literal_member(argument: true)
    end
    if allow_call_results && direct_call_start?
      return parse_direct_call(allow_call_result_arguments: false)
    end

    if allow_local_references && token.kind == :identifier
      reject(token) unless bare_local_reference_argument?

      return DabModernBootstrapLocalReference.new(next_token)
    end

    if token.kind == :interpolated_string && !allow_interpolated_strings
      reject(token, expectation)
    end

    unless executable_value?(token)
      reject(token) if deferred_call_argument_start?(token)

      reject(token, expectation)
    end

    token = next_token
    if token.kind == :integer && integer_overflow?(token.text)
      reject(token, 'Modern integer literal is outside supported range 0..9223372036854775807')
    end
    token
  end

  def argument_source_tokens(argument)
    return argument.source_tokens if argument.is_a?(DabModernBootstrapLiteralMemberCall)
    return argument.source_tokens if argument.is_a?(DabModernBootstrapLocalReference)
    return argument.source_tokens if argument.is_a?(DabModernBootstrapDirectCall)

    [argument]
  end

  def nested_property_tail?
    return false if peek_token.kind == :left_parenthesis
    return false if horizontal_whitespace?(peek_token) && token_after_horizontal_whitespace.kind == :left_parenthesis

    true
  end

  def bare_local_reference_argument?
    distance = 1
    distance += 1 while horizontal_whitespace?(peek_token(distance))
    %i[comma right_parenthesis].include?(peek_token(distance).kind)
  end

  def deferred_call_argument_start?(token)
    %i[identifier left_parenthesis question_mark bang dot equal unsupported].include?(token.kind)
  end

  def build_literal_member_call(
    receiver_token,
    dot_token,
    callable_name,
    arguments,
    source_tokens,
    closing_parenthesis: nil
  )
    DabModernBootstrapLiteralMemberCall.new(
      receiver_token: receiver_token,
      dot_token: dot_token,
      callable_name: callable_name,
      arguments: arguments,
      source_tokens: source_tokens,
      closing_parenthesis: closing_parenthesis
    )
  end

  def build_direct_call(callable_name, arguments, source_tokens, closing_parenthesis)
    DabModernBootstrapDirectCall.new(
      callable_name: callable_name,
      arguments: arguments,
      source_tokens: source_tokens,
      closing_parenthesis: closing_parenthesis
    )
  end

  def finish_guardable_item(item, separator_kind)
    return parse_postfix_guard(item) if postfix_guard_candidate?

    spacing_error = postfix_before_spacing_error_token
    reject(spacing_error, EXPECT_POSTFIX_SPACE_BEFORE_MESSAGE) if spacing_error

    expect_guardable_item_separator(separator_kind)
    item
  end

  def expect_guardable_item_separator(separator_kind)
    case separator_kind
    when :literal
      expect_literal_separator
    when :call
      expect_call_body_separator
    when :member_call
      expect_member_call_body_separator
    when :bare_return
      expect_bare_return_separator
    when :break
      expect_break_separator
    when :next
      expect_next_separator
    else
      raise ArgumentError.new("unknown Modern guardable-item separator kind #{separator_kind.inspect}")
    end
  end

  def expect_bare_return_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_BARE_RETURN_SEPARATOR_MESSAGE)
  end

  def expect_break_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_BREAK_SEPARATOR_MESSAGE)
  end

  def expect_next_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject_invalid_separator_after_spaces(token)
    reject(token, EXPECT_NEXT_SEPARATOR_MESSAGE)
  end

  def postfix_guard_candidate?
    peek_token.kind == :space && postfix_keyword?(peek_token(1))
  end

  def malformed_postfix_guard_prefix?
    !postfix_before_spacing_error_token.nil?
  end

  def postfix_before_spacing_error_token
    return peek_token if postfix_keyword?(peek_token)
    return unless horizontal_whitespace?(peek_token)

    distance = 0
    distance += 1 while horizontal_whitespace?(peek_token(distance))
    return unless postfix_keyword?(peek_token(distance))
    return if distance == 1 && peek_token.kind == :space

    return peek_token if peek_token.kind != :space

    peek_token(1)
  end

  def postfix_keyword?(token)
    token.kind == :identifier && %w[if unless].include?(token.text)
  end

  def parse_postfix_guard(guarded_item)
    space_token = next_token
    keyword_token = next_token
    space_message, condition_message, separator_message = postfix_guard_messages(keyword_token)

    condition_space_token = next_token
    reject(condition_space_token, space_message) unless condition_space_token.kind == :space
    reject(peek_token, space_message) if horizontal_whitespace?(peek_token)

    condition_token, condition = parse_if_condition(condition_message)
    condition_separator = expect_postfix_condition_separator(
      condition_token,
      separator_message,
      condition_message
    )
    DabModernBootstrapPostfixGuard.new(
      guarded_item: guarded_item,
      space_token: space_token,
      keyword_token: keyword_token,
      condition_space_token: condition_space_token,
      condition: condition,
      condition_separator: condition_separator
    )
  end

  def postfix_guard_messages(keyword_token)
    if keyword_token.text == 'if'
      [
        EXPECT_POSTFIX_IF_SPACE_MESSAGE,
        EXPECT_POSTFIX_IF_CONDITION_MESSAGE,
        EXPECT_POSTFIX_IF_SEPARATOR_MESSAGE,
      ]
    else
      [
        EXPECT_POSTFIX_UNLESS_SPACE_MESSAGE,
        EXPECT_POSTFIX_UNLESS_CONDITION_MESSAGE,
        EXPECT_POSTFIX_UNLESS_SEPARATOR_MESSAGE,
      ]
    end
  end

  def expect_postfix_condition_separator(condition_token, separator_message, condition_message)
    token = peek_token
    reject_invalid_separator(token)
    return next_token if separator?(token)

    if horizontal_whitespace?(token)
      distance = 0
      distance += 1 while horizontal_whitespace?(peek_token(distance))
      chained_keyword = peek_token(distance)
      reject(chained_keyword, CHAINED_POSTFIX_GUARD_MESSAGE) if postfix_keyword?(chained_keyword)
      reject_invalid_separator(chained_keyword)
      reject(token, separator_message)
    end

    reject(token, separator_message) if token.kind == :eof

    reject_if_condition_form(condition_token, condition_message)
  end

  def expect_call_body_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject(token, EXPECT_CALL_BODY_SEPARATOR_MESSAGE)
  end

  def expect_member_call_body_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    reject(token, EXPECT_MEMBER_CALL_BODY_SEPARATOR_MESSAGE)
  end

  def expect_let_body_separator
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    if token.kind == :space
      reject_invalid_separator_after_spaces(token)
      following = token_after_spaces
      if separator?(following) || %i[eof end carriage_return].include?(following.kind)
        reject(token, EXPECT_LET_SEPARATOR_MESSAGE)
      end
    end
    if %i[eof end nil boolean_true boolean_false integer string].include?(token.kind)
      reject(token, EXPECT_LET_SEPARATOR_MESSAGE)
    end

    reject(token)
  end

  def expect_local_body_separator(message)
    token = next_token
    reject_invalid_separator(token)
    return token if separator?(token)

    if token.kind == :space
      reject_invalid_separator_after_spaces(token)
      following = token_after_spaces
      if separator?(following) || %i[eof end carriage_return].include?(following.kind)
        reject(token, message)
      end
    end
    if %i[eof end nil boolean_true boolean_false integer string].include?(token.kind)
      reject(token, message)
    end

    reject(token)
  end

  def reject_integer_overflow(token)
    return unless token.kind == :integer && integer_overflow?(token.text)

    reject(token, 'Modern integer literal is outside supported range 0..9223372036854775807')
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

  def skip_body_separators
    loop do
      indented = consume_body_line_indentation
      reject(peek_value_token) if indented && peek_value_token.kind == :semicolon
      reject_invalid_separator(peek_value_token)
      break unless separator?(peek_value_token)

      next_token
    end
  end

  def consume_body_line_indentation
    return false unless peek_value_token.kind == :space && peek_value_token.source_location.column.zero?

    next_token while peek_value_token.kind == :space
    true
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

  def reject_invalid_separator_after_spaces(token)
    reject_invalid_separator(token_after_spaces) if token.kind == :space
  end

  def reject_value_token(token)
    reject(token, token.diagnostic_message) if token.diagnostic_message
  end

  def executable_value?(token)
    VALUE_KINDS.include?(token.kind) || regex_literal?(token)
  end

  def executable_literal?(token)
    LITERAL_KINDS.include?(token.kind) || regex_literal?(token)
  end

  def regex_literal?(token)
    DabModernBootstrapLiterals.regex_literal?(token)
  end

  def reject(token, message = DabModernBootstrapParseError::GENERIC_MESSAGE)
    raise DabModernBootstrapParseError.new(message, source_span: token.source_span)
  end
end

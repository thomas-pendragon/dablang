require 'spec_helper'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'sequential literal Modern when patterns' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'when-patterns.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source, unit = DabNodeUnit.new)
    parse(source).lower_into(unit)
  end

  def expect_error(source, message, offending, occurrence: :first, offset: nil, lower_document: false)
    action = proc do
      document = parse(source)
      document.lower_into(DabNodeUnit.new) if lower_document
    end
    expect(&action).to raise_error(DabModernBootstrapParseError) { |error|
      start = offset || (occurrence == :last ? source.rindex(offending) : source.index(offending))
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  def expect_eof_error(source, message)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.bytesize, source.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'parses zero or more ordered clauses containing every existing Modern literal kind' do
    source = <<~'DAB'
      def main(name:String)
      case name
      when nil
      when true
      when false
      when 9223372036854775807
      when "static"
      when "hello #{name}"
      end
      case false
      end
      end
    DAB
    statements = parse(source).declarations.fetch(0).body_items
    clauses = statements.fetch(0).when_clauses

    expect(clauses.map { |clause| clause.pattern.kind }).to eq(
      %i[nil boolean_true boolean_false integer string interpolated_string]
    )
    expect(clauses.map(&:body)).to all(be_empty)
    expect(statements.fetch(1).when_clauses).to be_empty
    expect(clauses).to all(be_frozen)
  end

  it 'freezes the subject once and lowers a lazy pattern-receiver equality chain with marked targets' do
    function = lower(<<~DAB)
      def main(subject:Fixnum)
      case subject
      when 1
      "one"
      when 2
      "two"
      when 3
      end
      end
    DAB
    definitions = function.blocks[0].all_nodes(DabNodeDefineLocalVar)
    comparisons = function.blocks[0].all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == '=='
    end

    expect(definitions.map { |definition| definition.real_identifier.to_s })
      .to contain_exactly(a_string_starting_with('$modern_case_subject_'))
    expect(comparisons.length).to eq(3)
    expect(comparisons).to all(be_compiler_verified_target)
    expect(comparisons.map { |call| call.value.constant_value }).to eq([1, 2, 3])
    expect(comparisons.map { |call| call.args.fetch(0).real_identifier.to_s }.uniq)
      .to eq([definitions.fetch(0).real_identifier.to_s])
    expect(function.blocks[0].all_nodes(DabNodeIf).length).to eq(3)
  end

  it 'keeps the marker default false, checks marked non-equality calls, and preserves equality rejection' do
    arguments = DabNode.new
    arguments.insert(DabNodeLiteralString.new('right'))
    ordinary = DabNodeInstanceCall.new(DabNodeLiteralString.new('left'), '==', arguments, nil)
    marked = DabNodeInstanceCall.new(
      DabNodeLiteralString.new('left'),
      '==',
      [DabNodeLiteralString.new('right')],
      nil,
      compiler_verified_target: true
    )
    marked_missing = DabNodeInstanceCall.new(
      DabNodeLiteralString.new('left'),
      'missing',
      DabNode.new,
      nil,
      compiler_verified_target: true
    )

    expect(ordinary).not_to be_compiler_verified_target
    expect(marked).to be_compiler_verified_target
    expect(marked_missing).to be_compiler_verified_target
    expect(DabType.parse('String')).not_to have_function('==')
    expect(CheckInstanceFunctionExistence.new.run(ordinary)).to be(true)
    expect(ordinary.errors).to contain_exactly(be_a(DabCompileUnknownMemberFunctionError))
    expect(CheckInstanceFunctionExistence.new.run(marked)).to be_nil
    expect(marked.errors).to be_empty
    expect(CheckInstanceFunctionExistence.new.run(marked_missing)).to be(true)
    expect(marked_missing.errors).to contain_exactly(be_a(DabCompileUnknownMemberFunctionError))
  end

  it 'traverses clauses by index without copying suffix arrays and preserves their order' do
    parsed = parse(<<~DAB).declarations.fetch(0).body_items.fetch(0)
      def main()
      case true
      when 1
      when 2
      when 3
      end
      end
    DAB
    no_drop_clauses = Class.new(Array) do
      def drop(*)
        raise 'clause suffix arrays must not be copied'
      end
    end.new(parsed.when_clauses)
    statement = DabModernBootstrapCaseStatement.new(
      case_token: parsed.case_token,
      space_token: parsed.space_token,
      subject: parsed.subject,
      subject_separator: parsed.subject_separator,
      when_clauses: no_drop_clauses,
      end_token: parsed.end_token,
      final_separator: parsed.final_separator
    )

    comparisons = statement.lower.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == '=='
    end
    expect(statement.else_clause).to be_nil
    expect(comparisons.map { |call| call.value.constant_value }).to eq([1, 2, 3])
  end

  it 'preserves contextual when declarations, calls, suffixes, locals, members, interpolation, and text' do
    source = <<~'DAB'
      def when(value:Boolean):Boolean
      return value
      end
      def when?(value:Boolean):Boolean
      return value
      end
      def names(when:String):String
      when(true)
      when?(false)
      "x".when()
      return "#{when} when"
      end
      def main()
      var when = true
      when = false
      case true
      when true
      when(false)
      when?(true)
      end
      end
    DAB
    document = parse(source)
    names = document.declarations.fetch(2).body_items
    clause_body = document.declarations.fetch(3).body_items.fetch(2).when_clauses.fetch(0).body

    expect(names.take(2).map { |item| item.callable_name.text }).to eq(%w[when when?])
    expect(names.fetch(2).callable_name.text).to eq('when')
    expect(names.fetch(3).value.value.splices.map(&:name)).to eq(['when'])
    expect(clause_body.map { |item| item.callable_name.text }).to eq(%w[when when?])
  end

  it 'parses existing when-local reassignments before rejecting them with the clause diagnostic' do
    ['when = false', 'when=false', "when\t=\tfalse"].each do |reassignment|
      source = <<~DAB
        def main()
        var when = true
        case true
        when true
        #{reassignment}
        end
        end
      DAB
      expect_error(
        source,
        DabModernBootstrapParser::CASE_CLAUSE_REASSIGNMENT_MESSAGE,
        'when',
        offset: source.index(reassignment)
      )
    end
  end

  it 'parses true clause boundaries and contextual when calls before semantic rejection' do
    source = <<~DAB
      def when(value:Boolean):Boolean
      return value
      end
      def when?(value:Boolean):Boolean
      return value
      end
      def main()
      var when = true
      case true
      when true
      when = false
      when false
      when(false)
      when?(true)
      when
      end
      end
    DAB
    malformed_when = source.rindex("when\n")

    expect_error(
      source,
      DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
      "\n",
      offset: malformed_when + 'when'.bytesize
    )
  end

  it 'accepts established nonbinding bodies recursively and lexical transfers only under while' do
    source = <<~DAB
      def main(flag:Boolean)
      while flag
      case true
      when false
      "literal"
      when true
      print("call") if true
      "text".length()
      if true
      unless false
      case nil
      when nil
      next
      end
      end
      end
      break
      end
      end
      end
    DAB
    expect { parse(source) }.not_to raise_error

    expect_error(
      "def main()\ncase true\nwhen true\nbreak\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_BREAK_MESSAGE,
      'break'
    )
    expect_error(
      "def main()\ncase true\nwhen true\nnext\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_NEXT_MESSAGE,
      'next'
    )
  end

  it 'rejects bindings and reassignments recursively after complete parsing' do
    cases = [
      [
        "def main()\ncase true\nwhen true\nlet value = true\nend\nend\n",
        DabModernBootstrapParser::CASE_CLAUSE_BINDING_MESSAGE,
        'let',
      ],
      [
        "def main()\ncase true\nwhen true\nif true\nvar value = true\nend\nend\nend\n",
        DabModernBootstrapParser::CASE_CLAUSE_BINDING_MESSAGE,
        'var',
      ],
      [
        "def main()\nvar value = true\ncase true\nwhen true\nvalue = false\nend\nend\n",
        DabModernBootstrapParser::CASE_CLAUSE_REASSIGNMENT_MESSAGE,
        'value',
        :last,
      ],
      [
        "def main()\nvar flag = true\ncase true\nwhen true\nwhile flag\nflag = false\nend\nend\nend\n",
        DabModernBootstrapParser::CASE_CLAUSE_REASSIGNMENT_MESSAGE,
        'flag',
        :last,
      ],
    ]
    cases.each do |source, message, offending, occurrence|
      expect_error(source, message, offending, occurrence: occurrence || :first)
    end

    malformed_tail = <<~DAB
      def main()
      case true
      when true
      let rejected = true
      when
      end
      end
    DAB
    expect_error(
      malformed_tail,
      DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
      "\n",
      occurrence: :last,
      offset: malformed_tail.index("\n", malformed_tail.rindex('when'))
    )
  end

  it 'preflights pattern interpolation, dead clause calls, and nested case subjects without a Ring' do
    accepted = <<~'DAB'
      def target(value:String):Boolean
      return true
      end
      def main(name:String)
      case target(name)
      when "#{name}"
      if false
      case target(name)
      when true
      end
      end
      end
      end
    DAB
    expect { parse(accepted) }.not_to raise_error

    expect_error(
      "def main()\ncase true\nwhen \"\#{missing}\"\nend\nend\n",
      'unknown Modern interpolation local "missing"; expected an earlier same-function local binding',
      'missing'
    )

    invalid = parse("def main()\ncase true\nwhen false\nmissing()\nend\nend\n")
    expect { invalid.lower_into(DabNodeUnit.new) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
  end

  it 'leaves a supplied unit unchanged when a clause preflight fails' do
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    document = parse(<<~DAB)
      def first()
      end
      def main()
      case true
      when false
      missing()
      end
      end
    DAB

    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'implements when spacing, pattern, separator, else, and body diagnostics with exact spans' do
    cases = [
      [
        "def main()\ncase true\nwhen\ttrue\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
        "\t",
      ],
      [
        "def main()\ncase true\nwhen \ttrue\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
        "\t",
      ],
      [
        "def main()\ncase true\nwhen \t true\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
        "\t",
      ],
      [
        "def main()\ncase true\nwhen  true\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_SPACE_MESSAGE,
        ' ',
        :last,
      ],
      [
        "def main()\ncase true\nwhen value\nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE,
        'value',
      ],
      [
        "def main()\ncase true\nwhen 1 \nend\nend\n",
        DabModernBootstrapParser::EXPECT_WHEN_PATTERN_SEPARATOR_MESSAGE,
        ' ',
        :last,
      ],
      [
        "def main()\ncase true\nprint(\"body\")\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_CLAUSE_OR_END_MESSAGE,
        'print',
      ],
    ]
    cases.each do |source, message, offending, occurrence|
      expect_error(source, message, offending, occurrence: occurrence || :first)
    end

    expect_eof_error("def main()\ncase true\nwhen ", DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE)
  end

  it 'uses full rejected-form spans and preserves scanner and call diagnostic precedence' do
    expect_error(
      "def main()\ncase true\nwhen value + 2\nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE,
      'value + 2'
    )
    expect_error(
      "def main()\ncase true\nwhen helper()\nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHEN_PATTERN_MESSAGE,
      'helper()'
    )
    expect_error(
      "def main()\ncase true\nwhen helper(,)\nend\nend\n",
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )
    source = "def main()\ncase true\nwhen \"unterminated\nend\nend\n"
    expect_error(
      source,
      'invalid Modern String literal: literal LF is not allowed; use "\\n"',
      "\n",
      offset: source.index("\n", source.index('"unterminated'))
    )
  end

  it 'accepts immediate separators and preserves CR and CRLF diagnostics' do
    source = <<~DAB
      def main()
      case true
      when nil;
      when true# hash
      when false# second hash
      end
      end
    DAB
    clauses = parse(source).declarations.fetch(0).body_items.fetch(0).when_clauses
    expect(clauses.map { |clause| clause.pattern_separator.kind })
      .to eq(%i[semicolon line_comment line_comment])

    ["\r", "\r\n"].each do |separator|
      expect_error(
        "def main()\ncase true\nwhen 1#{separator}end\nend\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end
  end
end

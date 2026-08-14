require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern if-elsif-else' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'if-else.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  it 'keeps elsif contextual across declarations, suffixes, and both direct-call forms' do
    source = <<~DAB
      def elsif(value:Boolean):Boolean
      return value
      end
      def elsif?(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      elsif(flag)
      elsif (flag)
      elsif?(flag)
      if false
      elsif flag
      end
      end
    DAB
    body = parse(source).declarations.fetch(2).body_items

    expect(body.take(3)).to all(be_a(DabModernBootstrapDirectCall))
    expect(body.take(3).map { |call| call.callable_name.text }).to eq(%w[elsif elsif elsif?])
    expect(body.fetch(3).elsif_clauses.length).to eq(1)
  end

  it 'builds ordered frozen clauses with exact source ownership and nearest nesting' do
    source = <<~DAB
      def main(first:Boolean,second:Boolean,third:Boolean)
      if first
      if false
      elsif second
      print("inner")
      end
      elsif second
      print("second")
      elsif third
      else
      print("fallback")
      end
      end
    DAB
    statement = parse(source).declarations.fetch(0).body_items.fetch(0)
    inner = statement.if_true.fetch(0)
    first_clause, second_clause = statement.elsif_clauses

    expect(inner.elsif_clauses.length).to eq(1)
    expect(statement.elsif_clauses).to be_frozen
    expect([first_clause, second_clause]).to all(be_frozen)
    expect([first_clause.body, first_clause.source_tokens, first_clause.source_parts]).to all(be_frozen)
    expect(first_clause.source_parts).to eq(['elsif', ' ', 'second', "\n"])
    expect(second_clause.source_parts).to eq(['elsif', ' ', 'third', "\n"])
    expect([first_clause.source_span.start_offset, first_clause.source_span.end_offset]).to eq(
      [source.index("elsif second\n", source.index("elsif second\n") + 1), source.index("elsif third\n")]
    )
    expect([second_clause.source_span.start_offset, second_clause.source_span.end_offset]).to eq(
      [source.index("elsif third\n"), source.index("else\n", source.index("elsif third\n"))]
    )
    expect(statement.end_token.text).to eq('end')
    expect(statement.source_span.end_offset).to eq(source.rindex("end\nend\n") + 4)
  end
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_error(source, message, offending, occurrence: :first)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      start = occurrence == :last ? source.rindex(offending) : source.index(offending)
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'keeps if and else contextual while building frozen nearest-owner structures' do
    source = <<~DAB
      def if(value:Boolean):Boolean
      return value
      end
      def else(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      if(flag)
      else(flag)
      if flag
      if false# inner
      print("wrong")
      else;print("inner")
      end;else
      print("outer")
      end
      end
    DAB
    document = parse(source)
    body = document.declarations.fetch(2).body_items
    statement = body.fetch(2)

    expect(body.take(2)).to all(be_a(DabModernBootstrapDirectCall))
    expect(statement).to be_a(DabModernBootstrapIfStatement)
    expect(statement).to be_frozen
    expect(statement.if_true).to be_frozen
    expect(statement.if_false).to be_frozen
    expect(statement.source_parts).to be_frozen
    expect([statement.source_span.start_offset, statement.source_span.end_offset]).to eq(
      [source.index('if flag'), source.rindex("end\nend\n") + 4]
    )
    expect(statement.if_true.fetch(0).if_false).not_to be_nil
    expect(statement.if_false.fetch(0).callable_name.text).to eq('print')
  end

  it 'accepts literal, Boolean parameter, and latest exact Boolean local conditions' do
    source = <<~DAB
      def main(flag:Boolean)
      var local = nil
      local = true
      if true;end
      if false# no
      end
      if flag;end
      if local;end
      end
    DAB
    document = parse(source)
    function = document.lower_into(DabNodeUnit.new)

    expect(function.blocks[0].all_nodes(DabNodeIf).length).to eq(4)
  end

  it 'lowers only through existing tree blocks and DabNodeIf with one condition read' do
    source = <<~DAB
      def choose(flag:Boolean):String
      if flag
      return "yes"
      else
      return "no"
      end
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    statement = function.blocks[0].all_nodes(DabNodeIf).fetch(0)

    expect(statement.if_true).to be_a(DabNodeTreeBlock)
    expect(statement.if_false).to be_a(DabNodeTreeBlock)
    expect(statement.condition).to be_a(DabNodeLocalVar)
    expect(statement.condition.identifier.to_s).to eq('flag')
  end

  it 'lowers clauses tail-to-head through nested DabNodeIf tree blocks in source order' do
    source = <<~DAB
      def choose(first:Boolean,second:Boolean,third:Boolean):String
      if first
      return "first"
      elsif second
      return "second"
      elsif third
      return "third"
      else
      return "fallback"
      end
      end
    DAB
    outer = parse(source).lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeIf).fetch(0)
    second = outer.if_false[0]
    third = second.if_false[0]

    expect([outer, second, third]).to all(be_a(DabNodeIf))
    expect([outer.if_true, outer.if_false, second.if_true, second.if_false,
            third.if_true, third.if_false]).to all(be_a(DabNodeTreeBlock))
    expect([outer.condition, second.condition, third.condition].map { |node| node.identifier.to_s })
      .to eq(%w[first second third])
  end

  it 'accepts zero, one, or many clauses with inherited Boolean condition forms' do
    source = <<~DAB
      def main(flag:Boolean)
      var local = nil
      local = true
      if false;end
      if false;elsif true;end
      if false
      elsif false
      elsif flag
      elsif local
      else
      end
      end
    DAB
    statements = parse(source).declarations.fetch(0).body_items.last(3)

    expect(statements.map { |statement| statement.elsif_clauses.length }).to eq([0, 1, 3])
    expect { parse(source).lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'rejects unsupported conditions with complete-form spans and exact precedence' do
    message = DabModernBootstrapParser::EXPECT_IF_CONDITION_MESSAGE
    {
      "def main()\nif nil\nend\nend\n" => 'nil',
      "def main()\nif true+false\nend\nend\n" => 'true+false',
      "def main()\nif (true)\nend\nend\n" => '(true)',
      "def main(value:String)\nif value\nend\nend\n" => 'value',
      "def main()\nvar value = true\nvalue = nil\nif value\nend\nend\n" => 'value',
    }.each do |source, offending|
      expect_error(source, message, offending, occurrence: :last)
    end
  end

  it 'requires exact header and delimiter separators and preserves CR diagnostics' do
    expect_error(
      "def main()\nif\ttrue\nend\nend\n",
      DabModernBootstrapParser::EXPECT_IF_SPACE_MESSAGE,
      "\t"
    )
    expect_error(
      "def main()\nif  true\nend\nend\n",
      DabModernBootstrapParser::EXPECT_IF_SPACE_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif true \nend\nend\n",
      DabModernBootstrapParser::EXPECT_IF_CONDITION_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif true\nelse \nend\nend\n",
      DabModernBootstrapParser::EXPECT_ELSE_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif true\nend \nend\n",
      DabModernBootstrapParser::EXPECT_IF_END_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif true\rend\nend\n",
      DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      "\r"
    )
    expect_error(
      "def main()\nif false\nelsif\ttrue\nend\nend\n",
      DabModernBootstrapParser::EXPECT_ELSIF_SPACE_MESSAGE,
      "\t"
    )
    expect_error(
      "def main()\nif false\nelsif  true\nend\nend\n",
      DabModernBootstrapParser::EXPECT_ELSIF_SPACE_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif false\nelsif true \nend\nend\n",
      DabModernBootstrapParser::EXPECT_ELSIF_CONDITION_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nif false\nelsif true\rend\nend\n",
      DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      "\r"
    )
  end

  it 'rejects unsupported elsif conditions with exact semantic and complete-form spans' do
    message = DabModernBootstrapParser::EXPECT_ELSIF_CONDITION_MESSAGE
    {
      "def main()\nif false\nelsif nil\nend\nend\n" => 'nil',
      "def main()\nif false\nelsif true+false\nend\nend\n" => 'true+false',
      "def main(value:String)\nif false\nelsif value\nend\nend\n" => 'value',
      "def main()\nvar value = true\nvalue = nil\nif false\nelsif value\nend\nend\n" => 'value',
    }.each do |source, offending|
      expect_error(source, message, offending, occurrence: :last)
    end
  end

  it 'rejects every branch binding and known reassignment, including nested and dead content' do
    binding_cases = [
      "def main()\nif false\nlet value = 1\nend\nend\n",
      "def main()\nif true\nreturn\nif false\nvar value = 1\nend\nend\nend\n",
      "def main()\nif false\nelsif true\nreturn\nvar value = 1\nend\nend\n",
    ]
    binding_cases.each do |source|
      keyword = source.include?('let ') ? 'let' : 'var'
      expect_error(source, DabModernBootstrapParser::BRANCH_BINDING_MESSAGE, keyword)
    end

    source = "def main()\nvar value = true\nif false\nreturn\nvalue = false\nend\nend\n"
    expect_error(
      source,
      DabModernBootstrapParser::BRANCH_REASSIGNMENT_MESSAGE,
      'value',
      occurrence: :last
    )

    source = "def main()\nvar value = true\nif false\nelsif false\nvalue = false\nend\nend\n"
    expect_error(
      source,
      DabModernBootstrapParser::BRANCH_REASSIGNMENT_MESSAGE,
      'value',
      occurrence: :last
    )
  end

  it 'reports dangling, duplicate, and unterminated structures at their owned spans' do
    expect_error(
      "def main()\nelse\nend\n",
      DabModernBootstrapParser::UNEXPECTED_ELSE_MESSAGE,
      'else'
    )
    expect_error(
      "def main()\nif true\nelse\nelse\nend\nend\n",
      DabModernBootstrapParser::DUPLICATE_ELSE_MESSAGE,
      'else',
      occurrence: :last
    )
    expect_error(
      "def main()\nelsif true\nend\n",
      DabModernBootstrapParser::UNEXPECTED_ELSIF_MESSAGE,
      'elsif'
    )
    expect_error(
      "def main()\nif true\nelse\nelsif false\nend\nend\n",
      DabModernBootstrapParser::DUPLICATE_ELSIF_MESSAGE,
      'elsif'
    )
    expect_error(
      "def main()\nif true\nend\nelsif false\nend\n",
      DabModernBootstrapParser::UNEXPECTED_ELSIF_MESSAGE,
      'elsif'
    )
    source = "def main()\nif true\n"
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_IF_END_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.bytesize, source.bytesize]
      )
    }
  end

  it 'parses complete branch structure before preflight and publishes no partial unit' do
    malformed_tail = "def main()\nif missing\nprint(,)\nend\nend\n"
    expect { parse(malformed_tail) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    malformed_clause = "def main()\nif missing\nelsif false\nprint(,)\nend\nend\n"
    expect { parse(malformed_clause) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    dead_call = "def main()\nif false\nreturn\nmissing()\nend\nend\n"
    document = parse(dead_call)
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty

    dead_clause_call = "def main()\nif true\nreturn\nelsif false\nmissing()\nend\nend\n"
    document = parse(dead_clause_call)
    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'emits one source-attributed frontend error with status 2 and no publication' do
    Dir.mktmpdir('dab-modern-if-else') do |directory|
      source_path = File.join(directory, 'invalid-condition.dabm')
      source = "def main()\nif nil\nend\nend\n"
      File.binwrite(source_path, source)
      missing_ring = File.join(directory, 'missing.dabcb')
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}",
        chdir: root
      )
      stderr = stderr.lines.reject { |line| line.start_with?('clipboard:', 'Using file-based') }.join

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(stderr).to eq(
        "compiler: #{source_path}:2:3: error: " \
        "#{DabModernBootstrapParser::EXPECT_IF_CONDITION_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['invalid-condition.dabm'])
    end
  end
end

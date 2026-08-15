require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern unless-else' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'unless.dabm', syntax_profile: DabSyntaxProfile::MODERN)
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

  it 'keeps unless contextual across declarations, suffixes, and both direct-call forms' do
    source = <<~DAB
      def unless(value:Boolean):Boolean
      return value
      end
      def unless?(value:Boolean):Boolean
      return value
      end
      def unless!(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      unless(flag)
      unless (flag)
      unless?(flag)
      unless!(flag)
      unless flag
      end
      end
    DAB
    body = parse(source).declarations.fetch(3).body_items

    expect(body.take(4)).to all(be_a(DabModernBootstrapDirectCall))
    expect(body.take(4).map { |call| call.callable_name.text })
      .to eq(%w[unless unless unless? unless!])
    expect(body.fetch(4)).to be_a(DabModernBootstrapUnlessStatement)
  end

  it 'builds a frozen exact-source wrapper with nearest mixed nesting' do
    source = <<~DAB
      def main(outer:Boolean,inner:Boolean)
      unless outer
      if inner
      print("inner-if")
      else
      unless false
      print("inner-unless")
      end
      end
      else
      print("outer-else")
      end
      end
    DAB
    statement = parse(source).declarations.fetch(0).body_items.fetch(0)
    inner_if = statement.unless_body.fetch(0)
    inner_unless = inner_if.if_false.fetch(0)

    expect(statement).to be_frozen
    expect([statement.unless_body, statement.else_body, statement.source_tokens, statement.source_parts])
      .to all(be_frozen)
    expect(statement.source_parts).to eq(['unless', ' ', 'outer', "\n", 'else', "\n", 'end', "\n"])
    expect(inner_if).to be_a(DabModernBootstrapIfStatement)
    expect(inner_unless).to be_a(DabModernBootstrapUnlessStatement)
    expect([statement.source_span.start_offset, statement.source_span.end_offset]).to eq(
      [source.index('unless outer'), source.rindex("end\nend\n") + 4]
    )
  end

  it 'accepts inherited Boolean conditions, empty arms, comments, and optional else' do
    source = <<~DAB
      def main(flag:Boolean)
      var local = nil
      local = true
      unless true;end
      unless false# false body
      end
      unless flag
      else
      end
      unless local
      end
      end
    DAB
    statements = parse(source).declarations.fetch(0).body_items.last(4)

    expect(statements).to all(be_a(DabModernBootstrapUnlessStatement))
    expect(statements.map { |statement| !statement.else_body.nil? }).to eq([false, false, true, false])
    expect { parse(source).lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'lowers through one existing DabNodeIf by swapping frozen tree-block arms' do
    source = <<~DAB
      def choose(flag:Boolean):String
      unless flag
      return "false"
      else
      return "true"
      end
      end
    DAB
    statement = parse(source).lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeIf).fetch(0)

    expect(statement.condition).to be_a(DabNodeLocalVar)
    expect(statement.condition.identifier.to_s).to eq('flag')
    expect([statement.if_true, statement.if_false]).to all(be_a(DabNodeTreeBlock))
    expect(statement.if_true[0]).to be_a(DabNodeReturn)
    expect(statement.if_false[0]).to be_a(DabNodeReturn)
    expect(statement.if_true[0].value.string).to eq('true')
    expect(statement.if_false[0].value.string).to eq('false')
  end

  it 'uses an empty true tree block when else is omitted' do
    source = "def main(flag:Boolean)\nunless flag\nprint(\"false\")\nend\nend\n"
    statement = parse(source).lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeIf).fetch(0)

    expect(statement.if_true).to be_a(DabNodeTreeBlock)
    expect(statement.if_true.count).to eq(0)
    expect(statement.if_false.count).to be > 0
  end

  it 'rejects unsupported conditions with semantic and complete-form spans' do
    message = DabModernBootstrapParser::EXPECT_UNLESS_CONDITION_MESSAGE
    {
      "def main()\nunless nil\nend\nend\n" => 'nil',
      "def main()\nunless true+false\nend\nend\n" => 'true+false',
      "def main()\nunless true.false\nend\nend\n" => 'true.false',
      "def main(value:String)\nunless value\nend\nend\n" => 'value',
      "def main()\nvar value = true\nvalue = nil\nunless value\nend\nend\n" => 'value',
    }.each do |source, offending|
      expect_error(source, message, offending, occurrence: :last)
    end
  end

  it 'requires exact spacing and established separators while preserving CR diagnostics' do
    expect_error(
      "def main()\nunless\ttrue\nend\nend\n",
      DabModernBootstrapParser::EXPECT_UNLESS_SPACE_MESSAGE,
      "\t"
    )
    expect_error(
      "def main()\nunless  true\nend\nend\n",
      DabModernBootstrapParser::EXPECT_UNLESS_SPACE_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nunless true \nend\nend\n",
      DabModernBootstrapParser::EXPECT_UNLESS_CONDITION_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nunless true\nend \nend\n",
      DabModernBootstrapParser::EXPECT_UNLESS_END_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nunless true\rend\nend\n",
      DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      "\r"
    )
  end

  it 'permanently rejects clause-shaped elsif but preserves an elsif direct call' do
    source = <<~DAB
      def elsif(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      unless flag
      elsif(flag)
      end
      end
    DAB
    statement = parse(source).declarations.fetch(1).body_items.fetch(0)
    expect(statement.unless_body.fetch(0)).to be_a(DabModernBootstrapDirectCall)

    expect_error(
      "def main()\nunless false\nelsif true\nend\nend\n",
      DabModernBootstrapParser::UNSUPPORTED_UNLESS_ELSIF_MESSAGE,
      'elsif'
    )
    expect_error(
      "def main()\nunless false\nelse\nelsif true\nend\nend\n",
      DabModernBootstrapParser::UNSUPPORTED_UNLESS_ELSIF_MESSAGE,
      'elsif'
    )
  end

  it 'rejects duplicate else and unterminated structure at exact owned spans' do
    expect_error(
      "def main()\nunless true\nelse\nelse\nend\nend\n",
      DabModernBootstrapParser::DUPLICATE_UNLESS_ELSE_MESSAGE,
      'else',
      occurrence: :last
    )
    source = "def main()\nunless true\n"
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_UNLESS_END_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset])
        .to eq([source.bytesize, source.bytesize])
    }
  end

  it 'rejects all branch bindings and known writes in nested, dead, and post-return content' do
    binding_cases = [
      "def main()\nunless false\nlet value = 1\nend\nend\n",
      "def main()\nunless true\nelse\nreturn\nvar value = 1\nend\nend\n",
      "def main()\nunless true\nunless false\nvar value = 1\nend\nend\nend\n",
    ]
    binding_cases.each do |source|
      keyword = source.include?('let ') ? 'let' : 'var'
      expect_error(source, DabModernBootstrapParser::UNLESS_BRANCH_BINDING_MESSAGE, keyword)
    end

    nested_if = "def main()\nunless true\nif false\nvar value = 1\nend\nend\nend\n"
    expect_error(nested_if, DabModernBootstrapParser::BRANCH_BINDING_MESSAGE, 'var')

    source = "def main()\nvar value = true\nunless false\nreturn\nvalue = false\nend\nend\n"
    expect_error(
      source,
      DabModernBootstrapParser::UNLESS_BRANCH_REASSIGNMENT_MESSAGE,
      'value',
      occurrence: :last
    )
  end

  it 'parses every dead and unselected arm before semantic preflight and publishes nothing' do
    malformed_tail = "def main()\nunless missing\nprint(,)\nend\nend\n"
    expect { parse(malformed_tail) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    dead_call = "def main()\nunless true\nreturn\nmissing()\nend\nend\n"
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
  end

  it 'emits one deterministic frontend error with status 2 and no filesystem publication' do
    Dir.mktmpdir('dab-modern-unless') do |directory|
      source_path = File.join(directory, 'invalid-condition.dabm')
      source = "def main()\nunless nil\nend\nend\n"
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
        "compiler: #{source_path}:2:7: error: " \
        "#{DabModernBootstrapParser::EXPECT_UNLESS_CONDITION_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['invalid-condition.dabm'])
    end
  end
end

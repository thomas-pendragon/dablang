require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern if-else' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'if-else.dabm', syntax_profile: DabSyntaxProfile::MODERN)
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
  end

  it 'rejects every branch binding and known reassignment, including nested and dead content' do
    binding_cases = [
      "def main()\nif false\nlet value = 1\nend\nend\n",
      "def main()\nif true\nreturn\nif false\nvar value = 1\nend\nend\nend\n",
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

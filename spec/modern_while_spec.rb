require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern while' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'while.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }

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

  it 'keeps while contextual across declarations, calls, suffixes, returns, and reassignment' do
    source = <<~DAB
      def while(value:Boolean):Boolean
      return value
      end
      def while?(value:Boolean):Boolean
      return value
      end
      def while!(value:Boolean):Boolean
      return value
      end
      def call_forms(flag:Boolean):Boolean
      while(flag)
      while (flag)
      while?(flag)
      while!(flag)
      return while(flag)
      end
      def local_target()
      var while = true
      while = false
      end
      def names(while:String):String
      "while".while()# while member and comment
      return "\#{while}"
      end
      def main(flag:Boolean)
      while flag
      return
      end
      end
    DAB
    declarations = parse(source).declarations
    declarations_by_name = declarations.to_h { |declaration| [declaration.callable_name.text, declaration] }
    calls = declarations_by_name.fetch('call_forms').body_items
    local_items = declarations_by_name.fetch('local_target').body_items
    names = declarations_by_name.fetch('names').body_items

    expect(calls.take(4)).to all(be_a(DabModernBootstrapDirectCall))
    expect(calls.take(4).map { |call| call.callable_name.text })
      .to eq(%w[while while while? while!])
    expect(calls.fetch(4)).to be_a(DabModernBootstrapValueReturn)
    expect(calls.fetch(4).value.callable_name.text).to eq('while')
    expect(local_items.map(&:class)).to eq(
      [DabModernBootstrapMutableLocalBinding, DabModernBootstrapLocalReassignment]
    )
    expect(names.fetch(0)).to be_a(DabModernBootstrapLiteralMemberCall)
    expect(names.fetch(0).receiver_token.value).to eq('while')
    expect(names.fetch(0).callable_name.text).to eq('while')
    expect(names.fetch(1).value.value.splices.map(&:name)).to eq(['while'])
    expect(declarations_by_name.fetch('main').body_items.fetch(0))
      .to be_a(DabModernBootstrapWhileStatement)

    expect_error(
      "def main()\nwhile = false\nend\n",
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'while'
    )
  end

  it 'builds frozen exact-source wrappers with nearest mixed-structure ownership' do
    source = <<~DAB
      def main(outer:Boolean,inner:Boolean)
      while outer# outer
      if inner
      while false;end
      else
      unless false
      return
      end
      end
      end
      end
    DAB
    statement = parse(source).declarations.fetch(0).body_items.fetch(0)
    conditional = statement.loop_items.fetch(0)
    nested = conditional.if_true.fetch(0)

    expect(statement).to be_frozen
    expect([statement.loop_items, statement.source_tokens, statement.source_parts]).to all(be_frozen)
    expect(statement.source_parts).to eq(['while', ' ', 'outer', '# outer', 'end', "\n"])
    expect(conditional).to be_a(DabModernBootstrapIfStatement)
    expect(nested).to be_a(DabModernBootstrapWhileStatement)
    expect([statement.source_span.start_offset, statement.source_span.end_offset]).to eq(
      [source.index('while outer'), source.rindex("end\nend\n") + 4]
    )
  end

  it 'accepts literal, Boolean parameter, and latest exact Boolean local conditions' do
    source = <<~DAB
      def main(flag:Boolean)
      var local = nil
      local = true
      while false;end
      while flag
      return
      end
      while local
      return
      end
      end
    DAB
    document = parse(source)
    function = document.lower_into(DabNodeUnit.new)
    loops = function.blocks[0].all_nodes(DabNodeWhile)

    expect(loops.length).to eq(3)
    expect(loops.fetch(0).condition).to be_a(DabNodeLiteralBoolean)
    expect(loops.drop(1).map { |loop| loop.condition.identifier.to_s }).to eq(%w[flag local])
  end

  it 'lowers empty and nested loops only through existing while and tree-block nodes' do
    source = <<~DAB
      def main(flag:Boolean)
      while false
      end
      while flag
      if true
      print("selected") if true
      end
      while false;end
      return
      end
      print("fallthrough")
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    loops = function.blocks[0].all_nodes(DabNodeWhile)

    expect(loops.length).to eq(3)
    expect(loops).to all(be_a(DabNodeWhile))
    expect(loops.map(&:on_block)).to all(be_a(DabNodeTreeBlock))
    expect(loops.fetch(0).on_block.to_a).to be_empty
    expect(loops.fetch(1).on_block.all_nodes(DabNodeIf).length).to eq(2)
  end

  it 'retains literal-true no-return structure without executing a hanging probe' do
    source = "def main()\nwhile true\nend\nend\n"
    loop_node = parse(source).lower_into(DabNodeUnit.new).blocks[0].all_nodes(DabNodeWhile).fetch(0)

    expect(loop_node.condition).to be_a(DabNodeLiteralBoolean)
    expect(loop_node.condition.boolean).to eq(true)
    expect(loop_node.on_block.to_a).to be_empty
  end

  it 'rejects unsupported conditions with complete-form and semantic-reference spans' do
    message = DabModernBootstrapParser::EXPECT_WHILE_CONDITION_MESSAGE
    {
      "def main()\nwhile nil\nend\nend\n" => 'nil',
      "def main()\nwhile true+false\nend\nend\n" => 'true+false',
      "def main(value:String)\nwhile value\nend\nend\n" => 'value',
      "def main()\nvar value = true\nvalue = nil\nwhile value\nend\nend\n" => 'value',
    }.each do |source, offending|
      expect_error(source, message, offending, occurrence: :last)
    end
  end

  it 'requires exact spaces and separators while preserving CR and EOF ownership' do
    expect_error(
      "def main()\nwhile\ttrue\nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHILE_SPACE_MESSAGE,
      "\t"
    )
    expect_error(
      "def main()\nwhile  true\nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHILE_SPACE_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nwhile true \nend\nend\n",
      DabModernBootstrapParser::EXPECT_WHILE_CONDITION_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nwhile true\nend \nend\n",
      DabModernBootstrapParser::EXPECT_WHILE_END_SEPARATOR_MESSAGE,
      ' ',
      occurrence: :last
    )
    expect_error(
      "def main()\nwhile true\rend\nend\n",
      DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      "\r"
    )

    source = "def main()\nwhile true\n"
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_WHILE_END_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.bytesize, source.bytesize]
      )
    }
  end

  it 'rejects every loop binding and reassignment, including nested and dead content' do
    binding_cases = [
      "def main()\nwhile false\nlet value = 1\nend\nend\n",
      "def main()\nwhile true\nreturn\nvar value = 1\nend\nend\n",
      "def main()\nwhile true\nif false\nlet value = 1\nend\nend\nend\n",
      "def main()\nwhile true\nunless false\nvar value = 1\nend\nend\nend\n",
      "def main()\nwhile true\nwhile false\nlet value = 1\nend\nend\nend\n",
    ]
    binding_cases.each do |source|
      keyword = source.include?('let ') ? 'let' : 'var'
      expect_error(source, DabModernBootstrapParser::WHILE_BODY_BINDING_MESSAGE, keyword)
    end

    source = <<~DAB
      def main()
      var value = true
      while false
      return
      if false
      value = false
      end
      end
      end
    DAB
    expect_error(
      source,
      DabModernBootstrapParser::WHILE_BODY_REASSIGNMENT_MESSAGE,
      'value',
      occurrence: :last
    )
  end

  it 'parses complete loop content before condition preflight and publishes no partial unit' do
    malformed_tail = "def main()\nwhile missing\nprint(,)\nend\nend\n"
    expect { parse(malformed_tail) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    dead_call = "def main()\nwhile false\nreturn\nmissing()\nend\nend\n"
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

  it 'reports pre-Ring loop failures with status 2 and no filesystem publication' do
    Dir.mktmpdir('dab-modern-while') do |directory|
      source_path = File.join(directory, 'invalid-condition.dabm')
      source = "def main()\nwhile nil\nend\nend\n"
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
        "compiler: #{source_path}:2:6: error: " \
        "#{DabModernBootstrapParser::EXPECT_WHILE_CONDITION_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['invalid-condition.dabm'])
    end
  end

  it 'preflights complete dead loop calls after Ring load without publishing output' do
    Dir.mktmpdir('dab-modern-while-ring') do |directory|
      lower = File.join(directory, 'stdlib.dabcb')
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        stdlib_frontend,
        "--output=#{lower}",
        chdir: root
      )
      expect([status.exitstatus, stdout]).to eq([0, "PASS #{lower}\n"])
      expect(stderr).not_to include('FAILED', 'exception:')

      source_path = File.join(directory, 'dead-call.dabm')
      File.binwrite(source_path, "def main()\nwhile false\nreturn\nmissing()\nend\nend\n")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{lower}",
        chdir: root
      )
      stderr = stderr.lines.reject { |line| line.start_with?('clipboard:', 'Using file-based') }.join

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(stderr).to eq(
        "compiler: #{source_path}:4:0: error: unknown Modern call target \"missing\"\n"
      )
      expect(Dir.children(directory).sort).to eq(%w[dead-call.dabm stdlib.dabca stdlib.dabcb])
    end
  end
end

require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded lexical Modern break' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'break.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_error(source, message, offending = nil, occurrence: :first)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      start = if offending
                if occurrence == :last
                  source.rindex(offending)
                elsif occurrence == :after_break
                  source.index(offending, source.index('break') + 5)
                else
                  source.index(offending)
                end
              else
                source.bytesize
              end
      finish = offending ? start + offending.bytesize : start
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([start, finish])
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'keeps break as an ordinary scanner identifier with exact source metadata' do
    source = "break break? break!\n".b
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    identifiers = tokens.select { |token| token.kind == :identifier }
    expect(identifiers.map(&:text)).to eq(%w[break break break])
    expect(identifiers.map { |token| [token.source_span.start_offset, token.source_span.end_offset] })
      .to eq([[0, 5], [6, 11], [13, 18]])
  end

  it 'preserves declarations, parameters, locals, reassignments, members, calls, and returns' do
    source = <<~DAB
      def break(value:Boolean):Boolean
      return value
      end
      def break?(value:Boolean):Boolean
      return value
      end
      def break!(value:Boolean):Boolean
      return value
      end
      def call_forms(flag:Boolean):Boolean
      break(flag)
      break (flag)
      break?(flag)
      break!(flag)
      return break(flag)
      end
      def names(break:String)
      print(break)
      end
      def locals()
      var break = true
      break = false
      "break".break()# break in a comment
      print("break")
      end
    DAB
    declarations = parse(source).declarations.to_h do |declaration|
      [declaration.callable_name.text, declaration]
    end
    calls = declarations.fetch('call_forms').body_items
    names = declarations.fetch('names').body_items
    locals = declarations.fetch('locals').body_items

    expect(calls.take(4)).to all(be_a(DabModernBootstrapDirectCall))
    expect(calls.take(4).map { |call| call.callable_name.text })
      .to eq(%w[break break break? break!])
    expect(calls.fetch(4)).to be_a(DabModernBootstrapValueReturn)
    expect(calls.fetch(4).value.callable_name.text).to eq('break')
    expect(names.fetch(0).arguments.fetch(0).name).to eq('break')
    expect(locals.map(&:class)).to eq(
      [
        DabModernBootstrapMutableLocalBinding,
        DabModernBootstrapLocalReassignment,
        DabModernBootstrapLiteralMemberCall,
        DabModernBootstrapDirectCall,
      ]
    )
    expect(locals.fetch(2).callable_name.text).to eq('break')

    expect_error(
      "def main()\nbreak = false\nend\n",
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'break'
    )
  end

  it 'accepts only immediate bare separators and the established postfix forms' do
    source = <<~DAB
      def main(flag:Boolean)
      while true
      break
      break;
      break# hash
      break// slash
      break if flag
      break unless false
      end
      end
    DAB
    loop_items = parse(source).declarations.fetch(0).body_items.fetch(0).loop_items

    expect(loop_items.take(4)).to all(be_a(DabModernBootstrapBreak))
    expect(loop_items.drop(4)).to all(be_a(DabModernBootstrapPostfixGuard))
    expect(loop_items.drop(4).map { |guard| guard.guarded_item.class })
      .to eq([DabModernBootstrapBreak, DabModernBootstrapBreak])
    expect(loop_items.drop(4).map { |guard| guard.keyword_token.text }).to eq(%w[if unless])
    expect(loop_items.flat_map(&:source_parts)).to include('break')
  end

  it 'builds frozen break wrappers and lowers only to tree-level break markers' do
    source = "def main()\nwhile true\nbreak;\nend\nend\n"
    item = parse(source).declarations.fetch(0).body_items.fetch(0).loop_items.fetch(0)

    expect(item).to be_frozen
    expect([item.source_tokens, item.source_parts]).to all(be_frozen)
    expect(item.source_parts).to eq(['break'])
    expect([item.source_span.start_offset, item.source_span.end_offset])
      .to eq([source.index('break'), source.index('break') + 5])

    function = parse(source).lower_into(DabNodeUnit.new)
    marker = function.blocks[0].all_nodes(DabNodeBreak).fetch(0)
    expect([marker.source_cstart, marker.source_cend]).to eq([source.index('break'), source.index('break') + 5])
    expect(function.blocks[0].all_nodes(DabNodeJump)).to be_empty
  end

  it 'rejects values, labels, spacing, members, and operators at the first offending byte' do
    message = DabModernBootstrapParser::EXPECT_BREAK_SEPARATOR_MESSAGE
    cases = {
      "def main()\nwhile true\nbreak 1\nend\nend\n" => ' ',
      "def main()\nwhile true\nbreak outer\nend\nend\n" => ' ',
      "def main()\nwhile true\nbreak # comment\nend\nend\n" => ' ',
      "def main()\nwhile true\nbreak:\nend\nend\n" => ':',
      "def main()\nwhile true\nbreak+1\nend\nend\n" => '+',
      "def main()\nwhile true\nbreak.member\nend\nend\n" => '.',
      "def main()\nwhile true\nbreak\t\nend\nend\n" => "\t",
    }
    cases.each do |source, offending|
      expect_error(source, message, offending, occurrence: :after_break)
    end
  end

  it 'preserves direct-call meaning for immediate and accepted spaced parentheses' do
    source = <<~DAB
      def break(value:Boolean):Boolean
      return value
      end
      def main()
      break(true)
      break (false)
      end
    DAB
    calls = parse(source).declarations.fetch(1).body_items
    expect(calls).to all(be_a(DabModernBootstrapDirectCall))
    expect(calls.map { |call| call.arguments.fetch(0).kind })
      .to eq(%i[boolean_true boolean_false])
  end

  it 'uses zero-width EOF and inherited full CR or CRLF separator ownership' do
    source = "def main()\nwhile true\nbreak"
    expect_error(source, DabModernBootstrapParser::EXPECT_BREAK_SEPARATOR_MESSAGE)

    ["\r", "\r\n"].each do |separator|
      cr_source = "def main()\nwhile true\nbreak#{separator}end\nend\n"
      expect_error(
        cr_source,
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end
  end

  it 'requires an enclosing lexical while in the same function at the full break token' do
    message = DabModernBootstrapParser::UNEXPECTED_BREAK_MESSAGE
    cases = [
      "def main()\nbreak\nend\n",
      "def main()\nif true\nbreak\nend\nend\n",
      "def main()\nwhile false\nend\nbreak\nend\n",
      "def first()\nwhile false\nend\nend\ndef second()\nbreak\nend\n",
      "def main()\nreturn\nbreak\nend\n",
    ]
    cases.each do |source|
      expect_error(source, message, 'break')
    end
  end

  it 'admits break recursively under bounded conditional and postfix structure' do
    source = <<~DAB
      def main(flag:Boolean)
      while true
      if false
      break
      elsif false
      break
      else
      unless false
      break if flag
      else
      break unless flag
      end
      end
      end
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    expect(function.blocks[0].all_nodes(DabNodeBreak).length).to eq(4)
    expect(function.blocks[0].all_nodes(DabNodeIf).length).to eq(5)
  end

  it 'binds each marker to the nearest while after block and starts unreachable continuations' do
    outer_break = DabNodeBreak.new
    inner_break = DabNodeBreak.new
    inner_body = DabNodeTreeBlock.new
    inner_body.insert(inner_break)
    inner_loop = DabNodeWhile.new(DabNodeLiteralBoolean.new(true), inner_body)
    outer_body = DabNodeTreeBlock.new
    outer_body.insert(inner_loop)
    outer_body.insert(outer_break)
    outer_body.insert(DabNodeNop.new)
    outer_loop = DabNodeWhile.new(DabNodeLiteralBoolean.new(true), outer_body)
    entry = DabNodeBasicBlock.new
    blocks = [entry]

    outer_after = outer_loop.build_from_tree(entry, blocks)

    expect(outer_break.target).to equal(outer_after)
    expect(inner_break.target).not_to equal(outer_after)
    expect(inner_break.target).to be_a(DabNodeBasicBlock)
    expect(blocks).to include(inner_break.target, outer_break.target)
    expect(blocks.all? do |block|
      block.to_a.each_cons(2).none? { |left, _right| left.is_a?(DabNodeBaseJump) }
    end).to eq(true)
  end

  it 'parses malformed post-break content before loop ownership or semantic preflight' do
    outside = "def main()\nbreak\nprint(,)\nend\n"
    expect_error(
      outside,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )

    inside = "def main()\nwhile true\nbreak\nprint(,)\nend\nend\n"
    expect_error(
      inside,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )
  end

  it 'preflights dead post-break calls before lowering and publishes no partial unit' do
    source = "def main()\nwhile true\nbreak\nmissing()\nend\nend\n"
    document = parse(source)
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

  it 'retains PL-009 guard-write validation after a runtime-selected break' do
    valid = <<~DAB
      def main()
      var running = true
      while running
      break
      running = false
      end
      end
    DAB
    expect { parse(valid).lower_into(DabNodeUnit.new) }.not_to raise_error

    invalid = valid.sub('running = false', 'running = nil')
    expect_error(
      invalid,
      DabModernBootstrapParser::EXPECT_WHILE_GUARD_REASSIGNMENT_VALUE_MESSAGE,
      'nil'
    )
  end

  it 'rejects loopless break before Ring I/O with no output publication' do
    Dir.mktmpdir('dab-modern-break') do |directory|
      source_path = File.join(directory, 'loopless.dabm')
      File.binwrite(source_path, "def main()\nbreak\nend\n")
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
        "compiler: #{source_path}:2:0: error: " \
        "#{DabModernBootstrapParser::UNEXPECTED_BREAK_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['loopless.dabm'])
    end
  end
end

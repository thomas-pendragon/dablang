require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded lexical Modern next' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'next.dabm', syntax_profile: DabSyntaxProfile::MODERN)
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
                elsif occurrence == :after_next
                  source.index(offending, source.index('next') + 4)
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

  it 'keeps next as an ordinary scanner identifier with exact source metadata' do
    source = "next next? next!\n".b
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    identifiers = tokens.select { |token| token.kind == :identifier }
    expect(identifiers.map(&:text)).to eq(%w[next next next])
    expect(identifiers.map { |token| [token.source_span.start_offset, token.source_span.end_offset] })
      .to eq([[0, 4], [5, 9], [11, 15]])
  end

  it 'preserves declarations, parameters, locals, reassignments, members, interpolation, calls, and returns' do
    source = <<~DAB
      def next(value:Boolean):Boolean
      return value
      end
      def next?(value:Boolean):Boolean
      return value
      end
      def next!(value:Boolean):Boolean
      return value
      end
      def call_forms(flag:Boolean):Boolean
      next(flag)
      next (flag)
      next?(flag)
      next!(flag)
      return next(flag)
      end
      def names(next:String)
      print(next)
      print("\#{next}")
      end
      def locals()
      var next = true
      next = false
      "next".next()# next in a comment
      print("next")
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
      .to eq(%w[next next next? next!])
    expect(calls.fetch(4)).to be_a(DabModernBootstrapValueReturn)
    expect(calls.fetch(4).value.callable_name.text).to eq('next')
    expect(names.fetch(0).arguments.fetch(0).name).to eq('next')
    expect(locals.map(&:class)).to eq(
      [
        DabModernBootstrapMutableLocalBinding,
        DabModernBootstrapLocalReassignment,
        DabModernBootstrapLiteralMemberCall,
        DabModernBootstrapDirectCall,
      ]
    )
    expect(locals.fetch(2).callable_name.text).to eq('next')
    expect(names.fetch(1).arguments.fetch(0).value.splices.fetch(0).name).to eq('next')

    expect_error(
      "def main()\nnext = false\nend\n",
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'next'
    )
  end

  it 'accepts only immediate bare separators and the established postfix forms' do
    source = <<~DAB
      def main(flag:Boolean)
      while true
      next
      next;
      next# hash
      next# second hash
      next if flag
      next unless false
      end
      end
    DAB
    loop_items = parse(source).declarations.fetch(0).body_items.fetch(0).loop_items

    expect(loop_items.take(4)).to all(be_a(DabModernBootstrapNext))
    expect(loop_items.drop(4)).to all(be_a(DabModernBootstrapPostfixGuard))
    expect(loop_items.drop(4).map { |guard| guard.guarded_item.class })
      .to eq([DabModernBootstrapNext, DabModernBootstrapNext])
    expect(loop_items.drop(4).map { |guard| guard.keyword_token.text }).to eq(%w[if unless])
    expect(loop_items.flat_map(&:source_parts)).to include('next')
  end

  it 'builds frozen next wrappers and lowers only to tree-level next markers' do
    source = "def main()\nwhile true\nnext;\nend\nend\n"
    item = parse(source).declarations.fetch(0).body_items.fetch(0).loop_items.fetch(0)

    expect(item).to be_frozen
    expect([item.source_tokens, item.source_parts]).to all(be_frozen)
    expect(item.source_parts).to eq(['next'])
    expect([item.source_span.start_offset, item.source_span.end_offset])
      .to eq([source.index('next'), source.index('next') + 4])

    function = parse(source).lower_into(DabNodeUnit.new)
    marker = function.blocks[0].all_nodes(DabNodeNext).fetch(0)
    expect([marker.source_cstart, marker.source_cend]).to eq([source.index('next'), source.index('next') + 4])
    expect(function.blocks[0].all_nodes(DabNodeJump)).to be_empty
  end

  it 'rejects values, labels, spacing, members, operators, and chained guards at exact spans' do
    message = DabModernBootstrapParser::EXPECT_NEXT_SEPARATOR_MESSAGE
    cases = {
      "def main()\nwhile true\nnext 1\nend\nend\n" => ' ',
      "def main()\nwhile true\nnext outer\nend\nend\n" => ' ',
      "def main()\nwhile true\nnext # comment\nend\nend\n" => ' ',
      "def main()\nwhile true\nnext:\nend\nend\n" => ':',
      "def main()\nwhile true\nnext+1\nend\nend\n" => '+',
      "def main()\nwhile true\nnext.member\nend\nend\n" => '.',
      "def main()\nwhile true\nnext\t\nend\nend\n" => "\t",
    }
    cases.each do |source, offending|
      expect_error(source, message, offending, occurrence: :after_next)
    end

    chained = "def main()\nwhile true\nnext if true unless false\nend\nend\n"
    expect_error(
      chained,
      DabModernBootstrapParser::CHAINED_POSTFIX_GUARD_MESSAGE,
      'unless'
    )
  end

  it 'preserves direct-call meaning for immediate and accepted spaced parentheses' do
    source = <<~DAB
      def next(value:Boolean):Boolean
      return value
      end
      def main()
      next(true)
      next (false)
      end
    DAB
    calls = parse(source).declarations.fetch(1).body_items
    expect(calls).to all(be_a(DabModernBootstrapDirectCall))
    expect(calls.map { |call| call.arguments.fetch(0).kind })
      .to eq(%i[boolean_true boolean_false])
  end

  it 'uses zero-width EOF and inherited full CR or CRLF separator ownership' do
    source = "def main()\nwhile true\nnext"
    expect_error(source, DabModernBootstrapParser::EXPECT_NEXT_SEPARATOR_MESSAGE)

    ["\r", "\r\n"].each do |separator|
      cr_source = "def main()\nwhile true\nnext#{separator}end\nend\n"
      expect_error(
        cr_source,
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end
  end

  it 'requires an enclosing lexical while in the same function at the full next token' do
    message = DabModernBootstrapParser::UNEXPECTED_NEXT_MESSAGE
    cases = [
      "def main()\nnext\nend\n",
      "def main()\nif true\nnext\nend\nend\n",
      "def main()\nwhile false\nend\nnext\nend\n",
      "def first()\nwhile false\nend\nend\ndef second()\nnext\nend\n",
      "def main()\nreturn\nnext\nend\n",
    ]
    cases.each do |source|
      expect_error(source, message, 'next')
    end
  end

  it 'admits next recursively under bounded conditional and postfix structure' do
    source = <<~DAB
      def main(flag:Boolean)
      while true
      if false
      next
      elsif false
      next
      else
      unless false
      next if flag
      else
      next unless flag
      end
      end
      end
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    expect(function.blocks[0].all_nodes(DabNodeNext).length).to eq(4)
    expect(function.blocks[0].all_nodes(DabNodeIf).length).to eq(5)
  end

  it 'binds each marker to the nearest while condition and preserves break ownership' do
    outer_next = DabNodeNext.new
    outer_break = DabNodeBreak.new
    inner_next = DabNodeNext.new
    inner_body = DabNodeTreeBlock.new
    inner_body.insert(inner_next)
    inner_loop = DabNodeWhile.new(DabNodeLiteralBoolean.new(true), inner_body)
    outer_body = DabNodeTreeBlock.new
    outer_body.insert(inner_loop)
    outer_body.insert(outer_next)
    outer_body.insert(outer_break)
    outer_body.insert(DabNodeNop.new)
    outer_loop = DabNodeWhile.new(DabNodeLiteralBoolean.new(true), outer_body)
    entry = DabNodeBasicBlock.new
    blocks = [entry]

    outer_after = outer_loop.build_from_tree(entry, blocks)

    expect(outer_break.target).to equal(outer_after)
    expect(outer_next.target).not_to equal(outer_after)
    expect(inner_next.target).not_to equal(outer_next.target)
    expect([outer_next.target, inner_next.target]).to all(be_a(DabNodeBasicBlock))
    expect(blocks).to include(outer_next.target, inner_next.target, outer_break.target)
    expect([outer_next.target, inner_next.target].map { |target| target.to_a.fetch(0).class })
      .to eq([DabNodeConditionalJump, DabNodeConditionalJump])
    expect(blocks.all? do |block|
      block.to_a.each_cons(2).none? { |left, _right| left.is_a?(DabNodeBaseJump) }
    end).to eq(true)
  end

  it 'parses malformed post-next content before loop ownership or semantic preflight' do
    outside = "def main()\nnext\nprint(,)\nend\n"
    expect_error(
      outside,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )

    inside = "def main()\nwhile true\nnext\nprint(,)\nend\nend\n"
    expect_error(
      inside,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )
  end

  it 'preflights dead post-next calls before lowering and publishes no partial unit' do
    source = "def main()\nwhile true\nnext\nmissing()\nend\nend\n"
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

  it 'retains guard-write validation after selected and conditionally unselected next items' do
    valid = <<~DAB
      def main(flag:Boolean)
      var running = true
      while running
      next if flag
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

  it 'represents next before the only terminating guard write without executing the infinite loop' do
    source = <<~DAB
      def main()
      var running = true
      while running
      next
      running = false
      end
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    loop_node = function.blocks[0].all_nodes(DabNodeWhile).fetch(0)
    marker = loop_node.all_nodes(DabNodeNext).fetch(0)
    entry = DabNodeBasicBlock.new
    blocks = [entry]

    loop_node.extract
    loop_node.build_from_tree(entry, blocks)
    expect(marker.target.to_a.fetch(0)).to be_a(DabNodeConditionalJump)
    expect(blocks.any? { |block| block.to_a.any?(DabNodeSetLocalVar) }).to eq(true)
  end

  it 'rejects loopless next before Ring I/O with no output publication' do
    Dir.mktmpdir('dab-modern-next') do |directory|
      source_path = File.join(directory, 'loopless.dabm')
      File.binwrite(source_path, "def main()\nnext\nend\n")
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
        "#{DabModernBootstrapParser::UNEXPECTED_NEXT_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['loopless.dabm'])
    end
  end
end

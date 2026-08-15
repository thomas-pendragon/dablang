require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'bounded Modern postfix guards' do
  let(:source_unit) do
    DabSourceUnit.new(input: 'postfix-guards.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def expect_error(source, message, offending, occurrence: :first, offset: nil)
    expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
      start = offset || (occurrence == :last ? source.rindex(offending) : source.index(offending))
      expect(error.message).to eq(message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start, start + offending.bytesize]
      )
      expect(error.source_span.source_unit).to equal(source_unit)
    }
  end

  it 'keeps if and unless as ordinary scanner identifiers and accepted callable names' do
    scanner = DabModernBootstrapScanner.new(
      "if unless if? unless!\n".b,
      source_unit: source_unit
    )
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end
    expect(tokens.select { |token| token.kind == :identifier }.map(&:text))
      .to eq(%w[if unless if unless])

    source = <<~DAB
      def if(value:Boolean):Boolean
      return value
      end
      def unless(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean):Boolean
      if(flag)
      unless (flag)
      return if(flag)
      end
    DAB
    document = parse(source)
    body = document.declarations.fetch(2).body_items

    expect(body.take(2)).to all(be_a(DabModernBootstrapDirectCall))
    expect(body.fetch(2)).to be_a(DabModernBootstrapValueReturn)
    expect(body.fetch(2).value).to be_a(DabModernBootstrapDirectCall)
    expect(body.fetch(2).value.callable_name.text).to eq('if')
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'wraps every established nonbinding simple item with exact frozen source ownership' do
    source = <<~DAB
      def helper(flag:Boolean):String
      return "helper"
      end
      def main(flag:Boolean)
      nil if true
      "value" unless false;
      helper(flag) if flag# call
      "abc".length unless flag
      return if false
      return "done" unless true
      end
    DAB
    guards = parse(source).declarations.fetch(1).body_items

    expect(guards).to all(be_a(DabModernBootstrapPostfixGuard))
    expect(guards.map { |guard| guard.guarded_item.kind }).to eq(
      %i[nil string direct_call literal_member_call bare_return value_return]
    )
    expect(guards.map { |guard| guard.keyword_token.text }).to eq(
      %w[if unless if unless if unless]
    )
    guards.each do |guard|
      expect(guard).to be_frozen
      expect([guard.source_tokens, guard.source_parts, guard.branch_items, guard.branch_item_groups])
        .to all(be_frozen)
      owned = source.byteslice(guard.source_span.start_offset...guard.source_span.end_offset)
      expect(guard.source_parts.map(&:to_s).join).to eq(owned)
      expect(guard.source_span.source_unit).to equal(source_unit)
    end
    expect(guards.fetch(0).source_parts.map(&:to_s)).to eq(['nil', ' ', 'if', ' ', 'true', "\n"])
    expect(guards.fetch(2).condition_separator.kind).to eq(:line_comment)
    expect(guards.fetch(5).source_span.end_offset).to eq(source.rindex("\nend\n") + 1)
  end

  it 'lowers only through existing DabNodeIf and tree blocks with the item inside the selected arm' do
    source = <<~DAB
      def main(flag:Boolean)
      print("a", "b") if flag
      print("c") unless flag
      end
    DAB
    function = parse(source).lower_into(DabNodeUnit.new)
    statements = function.blocks[0].to_a

    expect(statements).to all(be_a(DabNodeIf))
    expect(statements.map { |statement| statement.condition.class }).to eq(
      [DabNodeLocalVar, DabNodeLocalVar]
    )
    expect(statements.fetch(0).if_true).to be_a(DabNodeTreeBlock)
    expect(statements.fetch(0).if_true.to_a).to all(be_a(DabNodeCall))
    expect(statements.fetch(0).if_true.count).to eq(2)
    expect(statements.fetch(0).if_false.count).to eq(0)
    expect(statements.fetch(1).if_true.count).to eq(0)
    expect(statements.fetch(1).if_false.count).to eq(1)
  end

  it 'accepts inherited Boolean parameters and latest-flow locals only' do
    accepted = <<~DAB
      def main(flag:Boolean)
      var latest = nil
      latest = true
      print("parameter") if flag
      print("local") unless latest
      end
    DAB
    expect { parse(accepted).lower_into(DabNodeUnit.new) }.not_to raise_error

    cases = {
      'nil' => ["def main()\nprint(\"x\") if nil\nend\n", 'nil'],
      'String parameter' => ["def main(value:String)\nprint(\"x\") unless value\nend\n", 'value'],
      'latest non-Boolean local' => [
        "def main()\nvar value = true\nvalue = nil\nprint(\"x\") if value\nend\n",
        'value',
      ],
      'call condition' => ["def main()\nprint(\"x\") if helper()\nend\n", 'helper()'],
      'operator condition' => ["def main()\nprint(\"x\") unless true+false\nend\n", 'true+false'],
    }
    cases.each do |description, (source, offending)|
      message = if source.include?(' unless ')
                  DabModernBootstrapParser::EXPECT_POSTFIX_UNLESS_CONDITION_MESSAGE
                else
                  DabModernBootstrapParser::EXPECT_POSTFIX_IF_CONDITION_MESSAGE
                end
      aggregate_failures(description) do
        expect_error(source, message, offending, occurrence: :last)
      end
    end
  end

  it 'requires one ASCII space before and after the contextual keyword' do
    before = DabModernBootstrapParser::EXPECT_POSTFIX_SPACE_BEFORE_MESSAGE
    after_if = DabModernBootstrapParser::EXPECT_POSTFIX_IF_SPACE_MESSAGE
    after_unless = DabModernBootstrapParser::EXPECT_POSTFIX_UNLESS_SPACE_MESSAGE

    expect_error("def main()\nprint()if true\nend\n", before, 'if')
    expect_error("def main():String\nreturn \"value\"if true\nend\n", before, 'if')
    source = "def main()\nprint()  if true\nend\n"
    expect_error(source, before, ' ', offset: source.index('  if') + 1)
    source = "def main():String\nreturn \"value\"  unless true\nend\n"
    expect_error(source, before, ' ', offset: source.index('  unless') + 1)
    expect_error("def main()\nprint()\tif true\nend\n", before, "\t")
    expect_error("def main()\nprint() if(true)\nend\n", after_if, '(', occurrence: :last)
    source = "def main()\nprint() unless  true\nend\n"
    expect_error(source, after_unless, ' ', offset: source.index('  true') + 1)
    expect_error("def main()\nprint() unless\ttrue\nend\n", after_unless, "\t")
  end

  it 'requires an immediate established separator and never treats EOF as one' do
    if_message = DabModernBootstrapParser::EXPECT_POSTFIX_IF_SEPARATOR_MESSAGE
    unless_message = DabModernBootstrapParser::EXPECT_POSTFIX_UNLESS_SEPARATOR_MESSAGE

    expect { parse("def main()\nprint() if true;end\n") }.not_to raise_error
    expect { parse("def main()\nprint() unless false# adjacent\nend\n") }.not_to raise_error
    expect_error("def main()\nprint() if true \nend\n", if_message, ' ', occurrence: :last)
    source = "def main()\nprint() unless false end\n"
    expect_error(source, unless_message, ' ', offset: source.index(' end'))
    expect_error(
      "def main()\nprint() if true\rend\n",
      DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      "\r"
    )

    source = "def main()\nprint() if true"
    expect_error(source, if_message, '', offset: source.bytesize)
  end

  it 'rejects every same and mixed second guard at the second keyword' do
    message = DabModernBootstrapParser::CHAINED_POSTFIX_GUARD_MESSAGE
    %w[if unless].product(%w[if unless]).each do |first, second|
      source = "def main(first:Boolean,second:Boolean)\nprint() #{first} first #{second} second\nend\n"
      expect_error(source, message, second, occurrence: :last)
    end
  end

  it 'does not reinterpret structured statements, bindings, writes, or unknown assignment shapes' do
    structured = <<~DAB
      def main(flag:Boolean)
      if flag
      end if flag
      end
    DAB
    expect_error(
      structured,
      DabModernBootstrapParser::EXPECT_IF_END_SEPARATOR_MESSAGE,
      ' ',
      offset: structured.index('end if') + 3
    )

    binding = "def main()\nlet value = true if true\nend\n"
    expect_error(
      binding,
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      ' ',
      offset: binding.index(' if')
    )
    write = "def main()\nvar value = true\nvalue = false if true\nend\n"
    expect_error(
      write,
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      ' ',
      offset: write.index(' if')
    )
    assignment = "def main()\nunknown = true if true\nend\n"
    expect_error(assignment, DabModernBootstrapParseError::GENERIC_MESSAGE, 'unknown')
  end

  it 'keeps strings, comments, member names, and line-separated structure noncontextual' do
    source = <<~DAB
      def if(value:Boolean):Boolean
      return value
      end
      def main(flag:Boolean)
      print("if unless")
      # print("hidden") if flag
      "if".length
      if flag
      print("structured")
      end
      end
    DAB
    body = parse(source).declarations.fetch(1).body_items

    expect(body.map(&:class)).to eq(
      [DabModernBootstrapDirectCall, DabModernBootstrapLiteralMemberCall, DabModernBootstrapIfStatement]
    )
  end

  it 'parses malformed skipped and post-return content before condition preflight' do
    malformed = <<~DAB
      def main(value:String)
      return
      print(,) if value
      end
    DAB
    expect { parse(malformed) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    semantic = <<~DAB
      def main(value:String)
      return
      missing() if value
      end
    DAB
    expect { parse(semantic) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_POSTFIX_IF_CONDITION_MESSAGE
    )
  end

  it 'preflights selected and skipped calls transactionally before lowering any declaration' do
    source = <<~DAB
      def first()
      print("never") if false
      end
      def second()
      missing() unless true
      end
    DAB
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

  it 'reports pre-Ring guard failures with status 2 and no filesystem publication' do
    Dir.mktmpdir('dab-modern-postfix-guard') do |directory|
      source_path = File.join(directory, 'invalid-condition.dabm')
      File.binwrite(source_path, "def main()\nprint(\"never\") if nil\nend\n")
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
        "compiler: #{source_path}:2:18: error: " \
        "#{DabModernBootstrapParser::EXPECT_POSTFIX_IF_CONDITION_MESSAGE}\n"
      )
      expect(Dir.children(directory)).to eq(['invalid-condition.dabm'])
    end
  end
end

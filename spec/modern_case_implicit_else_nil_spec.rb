require 'spec_helper'

require 'digest'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'implicit nil for a Modern case without else' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:source_unit) do
    DabSourceUnit.new(input: 'case-implicit-else-nil.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parser(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit)
  end

  def parse(source)
    parser(source).parse
  end

  def parse_case(source)
    parser(source).send(:parse_case_statement, {})
  end

  def statement(source, index = 0)
    parse(source).declarations.fetch(0).body_items.grep(DabModernBootstrapCaseStatement).fetch(index)
  end

  def implicit_nils(node)
    node.all_nodes(DabNodeLiteralNil).select do |literal|
      literal.source_parts.empty? && literal.parent.instance_of?(DabNodeTreeBlock)
    end
  end

  def terminal_false_arm(node)
    branch = node.all_nodes(DabNodeIf).fetch(0)
    branch = branch.if_false.all_nodes(DabNodeIf).fetch(0) while branch.if_false.all_nodes(DabNodeIf).any?
    branch.if_false
  end

  def structure(node)
    identifier = node.real_identifier.to_s if node.respond_to?(:real_identifier)
    [node.class.name, identifier, node.to_a.map { |child| structure(child) }]
  end

  it 'adds one source-less nil after a zero-clause subject through complete and private parser entry points' do
    complete_source = "def main()\ncase true\nend\nend\n"
    complete = statement(complete_source)
    direct = parse_case("case true\nend\n")

    [complete, direct].each do |parsed|
      expect(parsed.else_clause).to be_nil
      expect(parsed.lower.to_a.map(&:class)).to eq([DabNodeLiteralBoolean, DabNodeLiteralNil])
      expect(implicit_nils(parsed.lower).length).to eq(1)
      expect(implicit_nils(parsed.lower).fetch(0).source_parts).to be_empty
    end
  end

  it 'puts exactly one nil only in the terminal false arm after all clauses and alternatives' do
    parsed = statement(<<~DAB)
      def main(value:Int32)
      case value
      when 1, 2
      "first"
      when 3
      "second"
      end
      end
    DAB
    lowered = parsed.lower
    nil_node = implicit_nils(lowered).fetch(0)
    comparisons = lowered.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == '=='
    end

    expect(lowered.all_nodes(DabNodeIf).length).to eq(2)
    expect(comparisons.length).to eq(3)
    expect(terminal_false_arm(lowered).to_a).to eq([nil_node])
    expect(lowered.all_nodes(DabNodeReturn)).to be_empty
  end

  it 'has the same lowering shape as written else nil without creating parser-level else source' do
    implicit_source = <<~DAB
      def main(value:Int32)
      case value
      when 1
      "selected"
      end
      end
    DAB
    explicit_source = <<~DAB
      def main(value:Int32)
      case value
      when 1
      "selected"
      else
      nil
      end
      end
    DAB
    implicit = statement(implicit_source)
    explicit = statement(explicit_source)
    implicit_nil = implicit_nils(implicit.lower).fetch(0)
    explicit_nil = explicit.lower.all_nodes(DabNodeLiteralNil).find { |literal| literal.source_parts.any? }

    expect(structure(implicit.lower)).to eq(structure(explicit.lower))
    expect(implicit.else_clause).to be_nil
    expect(explicit.else_clause).to be_a(DabModernBootstrapCaseElseClause)
    expect(implicit_nil.source_parts).to be_empty
    expect(explicit_nil.source_parts.map(&:to_s)).to eq(['nil'])
    expect([implicit.source_span.start_offset, implicit.source_span.end_offset]).to eq(
      [implicit_source.index('case'), implicit_source.index("end\nend\n") + "end\n".bytesize]
    )
  end

  it 'distinguishes missing else from written empty else and written else nil' do
    missing = statement("def main()\ncase true\nend\nend\n").lower
    empty = statement("def main()\ncase true\nelse\nend\nend\n").lower
    explicit_nil = statement("def main()\ncase true\nelse\nnil\nend\nend\n").lower

    expect(missing.to_a.map(&:class)).to eq([DabNodeLiteralBoolean, DabNodeLiteralNil])
    expect(empty.to_a.map(&:class)).to eq([DabNodeLiteralBoolean])
    expect(explicit_nil.to_a.map(&:class)).to eq([DabNodeLiteralBoolean, DabNodeLiteralNil])
    expect(implicit_nils(empty)).to be_empty
    expect(implicit_nils(explicit_nil)).to be_empty
    expect(explicit_nil.all_nodes(DabNodeLiteralNil).fetch(0).source_parts).not_to be_empty
  end

  it 'keeps subject-once, source order, shared bodies, and lazy or reached Regex errors before fallback' do
    parsed = statement(<<~DAB)
      def main(subject:String)
      case subject
      when "ordinary", /first/, /[/
      "selected-once"
      when /last/
      "later-body"
      end
      end
    DAB
    lowered = parsed.lower
    comparisons = lowered.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == '=='
    end
    constructors = lowered.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == 'new'
    end
    matches = lowered.all_nodes(DabNodeInstanceCall).select do |call|
      call.real_identifier.to_s == DabModernBootstrapCaseStatement::REGEX_MATCH_TARGET
    end

    expect(lowered.all_nodes(DabNodeDefineLocalVar).length).to eq(1)
    expect((comparisons + matches).map { |call| call.args.fetch(0).real_identifier.to_s }.uniq.length)
      .to eq(1)
    expect([constructors.length, matches.length]).to eq([3, 3])
    expect(constructors.map { |call| call.args.fetch(0).constant_value }).to eq(['first', '[', 'last'])
    expect(lowered.all_nodes(DabNodeLiteralString).count do |literal|
      literal.constant_value == 'selected-once'
    end).to eq(1)
    expect(terminal_false_arm(lowered).to_a).to eq([implicit_nils(lowered).fetch(0)])
  end

  it 'keeps empty selection, nesting, dead tails, post-transfer placement, and post-case continuation' do
    source = <<~DAB
      def main(flag:Boolean)
      case true
      when true
      end
      print("after-case")
      if flag
      case false
      when true
      "dead-branch"
      end
      end
      while false
      case nil
      when nil
      "loop"
      end
      break
      case 1
      when 1
      "post-break"
      end
      end
      return
      case 2
      when 2
      "post-return"
      end
      end
    DAB
    document = parse(source)
    cases = []
    collect = lambda do |items|
      items.each do |item|
        case item
        when DabModernBootstrapCaseStatement
          cases << item
          item.when_clauses.each { |clause| collect.call(clause.body) }
        when DabModernBootstrapIfStatement
          item.branch_item_groups.each { |group| collect.call(group) }
        when DabModernBootstrapWhileStatement
          collect.call(item.loop_items)
        end
      end
    end
    collect.call(document.declarations.fetch(0).body_items)

    expect(cases.length).to eq(5)
    expect(cases.map { |case_statement| implicit_nils(case_statement.lower).length }).to all(eq(1))
    expect(document.declarations.fetch(0).body_items.fetch(1)).to be_a(DabModernBootstrapDirectCall)
    expect(cases.fetch(0).when_clauses.fetch(0).body).to be_empty
  end

  it 'leaves declared-return fallthrough to AddMissingReturn and never turns the fallback into return nil' do
    function = parse(<<~DAB).lower_into(DabNodeUnit.new)
      def main():String
      case false
      when true
      return "selected"
      end
      end
    DAB
    case_tree = function.blocks[0].to_a.fetch(0)

    expect(implicit_nils(case_tree).length).to eq(1)
    expect(implicit_nils(case_tree).fetch(0).parent).to be_a(DabNodeTreeBlock)
    expect(case_tree.all_nodes(DabNodeReturn).length).to eq(1)
    expect(AddMissingReturn.new.run(function)).to be(true)
    expect(function.blocks[0].last_node).to be_a(DabNodeReturn)
    expect(function.blocks[0].last_node.value).to be_a(DabNodeLiteralNil)
  end

  it 'remains statement-only and structurally rejects expression-position near misses' do
    cases = [
      "def main()\nreturn case true\nwhen true\nend\nend\n",
      "def main()\nlet result = case true\nwhen true\nend\nend\n",
      "def main()\nprint(case true)\nend\n",
    ]

    cases.each do |source|
      expect { parse(source) }.to raise_error(DabModernBootstrapParseError) { |error|
        offset = source.index('case')
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
        expect([error.source_span.start_offset, error.source_span.end_offset])
          .to eq([offset, offset + 'case'.bytesize])
      }
    end
  end

  it 'removes the side-effect-free implicit nil through the existing unused-value pass' do
    zero = parse_case("case effect()\nend\n").lower
    clauses = statement("def main()\ncase true\nwhen false\n\"body\"\nend\nend\n").lower
    terminal = terminal_false_arm(clauses)

    expect(StripUnusedValues.new.run(zero)).to be(true)
    expect(zero.to_a.map(&:class)).to eq([DabNodeCall])
    expect(StripUnusedValues.new.run(terminal)).to be(true)
    expect(terminal.to_a).to be_empty
  end

  it 'keeps complete-document failures transactional with no implicit parser wrapper published' do
    malformed = <<~DAB
      def main()
      case true
      when true
      end
      print(,)
      end
    DAB
    expect { parse(malformed) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    document = parse(<<~DAB)
      def effect():Boolean
      return true
      end
      def main()
      case effect()
      when true
      end
      missing()
      end
    DAB
    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'locks fixtures 0106 through 0111 and one Legacy control byte-for-byte' do
    expected_hashes = {
      'test/modern_source/0106_case_subject_once.dabmtest' =>
        'd4e8644ab322d7cfed13dad7b10369163c74d164470997d802257c50138f8e98',
      'test/modern_source/0107_literal_when_patterns.dabmtest' =>
        '03e28737c1182c9bb070664c7fe5040d8121b5e57bb9be08908e291df5cc5abf',
      'test/modern_source/0108_comma_when_alternatives.dabmtest' =>
        '0a27f2efff0139e1606ae51cbb736f789a31bad5f93145643ed3e09e0f301344',
      'test/modern_source/0109_select_with_case.dabmtest' =>
        '5d6f7e67ad4cbc95d4938d98de370640467cafe0e9b6ddad06f61bd92cf067ae',
      'test/modern_source/0110_regex_literal_lexing.dabmtest' =>
        'c3a1bc02ecb4bec9cfae0f24da33450dda32035d6b235e445d394b1f1939c420',
      'test/modern_source/0111_regex_case_matching.dabmtest' =>
        '70bbd5cdffca2e1099e3252687831359f159284f58bbc1abcef299dcea3fa3a8',
      'test/dab/0001_simple.dabt' =>
        '80d873bffa730e0a18bc25bf4c13ff572f34f245c0245e04580d388ea0214c54',
    }

    expected_hashes.each do |path, expected_hash|
      normalized = File.binread(File.join(root, path)).gsub("\r\n", "\n")
      expect(Digest::SHA256.hexdigest(normalized)).to eq(expected_hash)
    end
  end
end

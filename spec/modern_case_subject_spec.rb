require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'exactly-once empty Modern case shell' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:source_unit) do
    DabSourceUnit.new(input: 'case-subject.dabm', syntax_profile: DabSyntaxProfile::MODERN)
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def lower(source, unit = DabNodeUnit.new)
    parse(source).lower_into(unit)
  end

  def expect_error(source, message, offending, occurrence: :first, lower_document: false, offset: nil)
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

  def invoke(*command)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-case-subject-bundler')}
    Open3.capture3(environment, *command, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq([0, "PASS #{artifact}\n"])
    expect(tool_stderr(stderr)).not_to include('FAILED', 'exception:')
    artifact
  end

  def compile_source(source, directory, lower_ring, basename)
    path = File.join(directory, "#{basename}.dabm")
    File.binwrite(path, source)
    stdout, stderr, status = invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower_ring}")
    expect([status.exitstatus, tool_stderr(stderr)]).to eq([0, ''])
    stdout
  end

  it 'keeps case, when, and else contextual across declarations, names, calls, locals, members, and text' do
    source = <<~DAB
      def case(value:Boolean):Boolean
      return value
      end
      def case?(value:Boolean):Boolean
      return value
      end
      def case!(value:Boolean):Boolean
      return value
      end
      def when(value:Boolean):Boolean
      return value
      end
      def else(value:Boolean):Boolean
      return value
      end
      def call_forms(flag:Boolean):Boolean
      case(flag)
      case (flag)
      case?(flag)
      case!(flag)
      when(flag)
      else(flag)
      return case(flag)
      end
      def local_target()
      var case = true
      case = false
      end
      def names(case:String,when:String,else:String):String
      "case".case()# case when else
      return "\#{case}-\#{when}-\#{else}"
      end
      def structural(flag:Boolean)
      case flag
      end
      if true
      case false;end;
      else
      case true# subject
      # empty
      end# close
      end
      end
    DAB
    declarations = parse(source).declarations.to_h { |declaration| [declaration.callable_name.text, declaration] }
    calls = declarations.fetch('call_forms').body_items
    local_items = declarations.fetch('local_target').body_items
    names = declarations.fetch('names').body_items

    expect(calls.take(6)).to all(be_a(DabModernBootstrapDirectCall))
    expect(calls.take(6).map { |call| call.callable_name.text })
      .to eq(%w[case case case? case! when else])
    expect(calls.fetch(6)).to be_a(DabModernBootstrapValueReturn)
    expect(calls.fetch(6).value.callable_name.text).to eq('case')
    expect(local_items.map(&:class)).to eq(
      [DabModernBootstrapMutableLocalBinding, DabModernBootstrapLocalReassignment]
    )
    expect(names.fetch(0)).to be_a(DabModernBootstrapLiteralMemberCall)
    expect(names.fetch(0).callable_name.text).to eq('case')
    expect(names.fetch(1).value.value.splices.map(&:name)).to eq(%w[case when else])
    expect(declarations.fetch('structural').body_items.map(&:class)).to eq(
      [DabModernBootstrapCaseStatement, DabModernBootstrapIfStatement]
    )

    expect_error(
      "def main()\ncase?\nend\n",
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'case'
    )
    expect_error(
      "def main()\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_END_MESSAGE,
      'end',
      occurrence: :last
    )
  end

  it 'builds frozen wrappers and lowers every bounded subject through one existing tree-block child' do
    source = <<~DAB
      def effect():Boolean
      return true
      end
      def main(parameter:String)
      let local = "local"
      case nil;end;
      case true;end;
      case false;end;
      case 7;end;
      case "text";end;
      case "\#{parameter}";end;
      case local;end;
      case parameter;end;
      case effect();end;
      end
    DAB
    document = parse(source)
    statements = document.declarations.fetch(1).body_items.grep(DabModernBootstrapCaseStatement)

    expect(statements.length).to eq(9)
    expect(statements).to all(be_frozen)
    expect(statements.map(&:else_clause)).to all(be_nil)
    expect(statements.flat_map { |statement| [statement.source_tokens, statement.source_parts] })
      .to all(be_frozen)
    expect(statements.map { |statement| statement.lower.to_a.length }).to all(eq(1))
    expect(statements.map { |statement| statement.lower.to_a.fetch(0).class }).to eq(
      [
        DabNodeLiteralNil,
        DabNodeLiteralBoolean,
        DabNodeLiteralBoolean,
        DabNodeLiteralNumber,
        DabNodeLiteralString,
        DabNodeModernInterpolatedString,
        DabNodeLocalVar,
        DabNodeLocalVar,
        DabNodeCall,
      ]
    )
    expect(statements.last.lower.to_a.fetch(0).real_identifier).to eq('effect')
    expect([statements.first.source_span.start_offset, statements.first.source_span.end_offset]).to eq(
      [source.index('case nil'), source.index('case nil') + 'case nil;end;'.bytesize]
    )
    expect { document.lower_into(DabNodeUnit.new) }.not_to raise_error
  end

  it 'accepts multiple shells in order and recursive selected, unselected, loop, and dead-tail placement' do
    source = <<~DAB
      def first():Boolean
      return true
      end
      def second():Boolean
      return false
      end
      def main(flag:Boolean)
      case first();end;
      case second();end;
      if flag
      case true;end;
      elsif false
      case false;end;
      else
      case nil;end;
      end
      unless flag
      case 1;end;
      else
      case 2;end;
      end
      while false
      case "loop";end;
      break
      case first();end;
      next
      case second();end;
      end
      return
      case "post-return";end;
      end
    DAB
    functions = lower(source)
    main = functions.fetch(2)
    calls = main.blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)

    expect(calls).to eq(%w[first second first second])
    expect(main.blocks[0].all_nodes(DabNodeIf).length).to be >= 2
    expect(main.blocks[0].all_nodes(DabNodeWhile).length).to eq(1)
  end

  it 'accepts immediate LF, semicolon, and adjacent hash or slash comments only' do
    source = <<~DAB
      def main()
      case true
      end
      case false;# header
      # empty
      end;// close
      case nil// header
      // empty
      end# close
      end
    DAB
    statements = parse(source).declarations.fetch(0).body_items

    expect(statements).to all(be_a(DabModernBootstrapCaseStatement))
    expect(statements.map { |statement| statement.subject_separator.kind })
      .to eq(%i[line_feed semicolon line_comment])
    expect(statements.map { |statement| statement.final_separator.kind })
      .to eq(%i[line_feed semicolon line_comment])
  end

  it 'preserves zero-clause case diagnostics with exact token and EOF spans' do
    cases = [
      [
        "def main()\ncase\ttrue\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_SPACE_MESSAGE,
        "\t",
      ],
      [
        "def main()\ncase  true\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_SPACE_MESSAGE,
        ' ',
        :last,
      ],
      [
        "def main()\ncase \nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_SUBJECT_MESSAGE,
        "\n",
      ],
      [
        "def main()\ncase true \nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_SUBJECT_SEPARATOR_MESSAGE,
        ' ',
        :last,
      ],
      [
        "def main()\ncase true\nprint(\"body\")\nend\nend\n",
        DabModernBootstrapParser::EXPECT_CASE_CLAUSE_OR_END_MESSAGE,
        'print',
      ],
      [
        "def main()\ncase true\nend",
        DabModernBootstrapParser::EXPECT_CASE_END_SEPARATOR_MESSAGE,
        '',
      ],
    ]

    cases.each do |source, message, offending, occurrence|
      if offending.empty?
        expect_eof_error(source, message)
      else
        offset = message == DabModernBootstrapParser::EXPECT_CASE_SUBJECT_MESSAGE ? source.index("\n", source.index('case ')) : nil
        expect_error(source, message, offending, occurrence: occurrence || :first, offset: offset)
      end
    end

    expect_eof_error(
      "def main()\ncase true\n",
      DabModernBootstrapParser::EXPECT_CASE_END_MESSAGE
    )
  end

  it 'retains inherited CR and CRLF diagnostics and nearest or extra end ownership' do
    ["\r", "\r\n"].each do |separator|
      expect_error(
        "def main()\ncase true#{separator}end\nend\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
      expect_error(
        "def main()\ncase true\nend#{separator}end\n",
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        separator
      )
    end

    expect_error(
      "def main()\ncase true\nend\nend\nend\n",
      DabModernBootstrapParser::UNEXPECTED_END_MESSAGE,
      'end',
      occurrence: :last
    )
  end

  it 'rejects body items and unsupported complete subject forms without consuming later rows' do
    expectation = DabModernBootstrapParser::EXPECT_CASE_SUBJECT_MESSAGE
    {
      'nil.length' => 'nil.length',
      '"x".length()' => '"x".length()',
    }.each do |subject, offending|
      source = "def main()\ncase #{subject}\nend\nend\n"
      expect_error(source, expectation, offending)
    end

    {
      "def main()\ncase true+false\nend\nend\n" => '+',
      "def main()\ncase true == false\nend\nend\n" => ' ',
      "def main()\ncase true if true\nend\nend\n" => ' ',
    }.each do |source, offending|
      offset = source.index(offending, source.index('case true') + 'case true'.bytesize)
      expect_error(
        source,
        DabModernBootstrapParser::EXPECT_CASE_SUBJECT_SEPARATOR_MESSAGE,
        offending,
        offset: offset
      )
    end

    %w[nil let if unless while return break next when? else?].each do |item|
      source = "def main()\ncase true\n#{item}\nend\nend\n"
      token = item.delete_suffix('?')
      expect_error(source, DabModernBootstrapParser::EXPECT_CASE_CLAUSE_OR_END_MESSAGE, token)
    end
  end

  it 'gives scanner and current call diagnostics precedence over case diagnostics' do
    source = "def main()\ncase \"unterminated\nend\nend\n"
    expect_error(
      source,
      'invalid Modern String literal: literal LF is not allowed; use "\\n"',
      "\n",
      offset: source.index("\n", source.index('"unterminated'))
    )
    expect_error(
      "def main()\ncase producer(,)\nend\nend\n",
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE,
      ','
    )
    expect_error(
      "def main()\ncase producer(nested())\nend\nend\n",
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'nested'
    )
  end

  it 'preflights earlier locals, parameters, interpolation, and forward same-document calls without a Ring' do
    source = <<~DAB
      def main(parameter:String)
      let local = "local"
      case local;end;
      case parameter;end;
      case "\#{local}-\#{parameter}";end;
      case forward(local);end;
      end
      def forward(value:String):Boolean
      return true
      end
    DAB
    expect { parse(source) }.not_to raise_error

    expect_error(
      "def main()\ncase later\nend\nlet later = true\nend\n",
      DabModernBootstrapParser::EXPECT_CASE_SUBJECT_MESSAGE,
      'later'
    )
    expect_error(
      "def main()\ncase \"\#{later}\"\nend\nend\n",
      'unknown Modern interpolation local "later"; expected an earlier same-function local binding',
      'later'
    )
    expect_error(
      "def main()\ncase missing()\nend\nend\n",
      'unknown Modern call target "missing"',
      'missing'
    )
  end

  it 'preflights same-document subject-call arity and argument values before Ring I/O' do
    expect_error(
      "def producer(value:Boolean):Boolean\nreturn value\nend\ndef main()\ncase producer()\nend\nend\n",
      'incorrect Modern call arity for "producer": got 0, expected 1',
      'producer()'
    )
    expect_error(
      "def producer(value:Boolean):Boolean\nreturn value\nend\ndef main()\ncase producer(\"wrong\")\nend\nend\n",
      'cannot pass Modern argument of type String to parameter "value" of type Boolean in call "producer"',
      '"wrong"'
    )
    expect_error(
      "def main()\ncase print(\"effect\")\nend\nend\n",
      'unknown Modern call target "print"',
      'print'
    )
  end

  it 'parses the complete document before semantic preflight and leaves a destination unit unchanged' do
    malformed_tail = <<~DAB
      def main()
      case missing
      end
      print(,)
      end
    DAB
    expect { parse(malformed_tail) }.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    unit = DabNodeUnit.new
    existing = DabNodeFunction.new('existing', DabNodeTreeBlock.new, DabNode.new)
    unit.add_function(existing)
    invalid = <<~DAB
      def effect():Boolean
      return true
      end
      def main()
      case effect()
      end
      missing()
      end
    DAB
    document = parse(invalid)
    expect { document.lower_into(unit) }.to raise_error(
      DabModernBootstrapParseError,
      'unknown Modern call target "missing"'
    )
    expect(unit.functions.to_a).to eq([existing])
    expect(unit.constants.to_a).to be_empty
  end

  it 'rejects Ring-independent subject failures before a missing Ring and publishes nothing' do
    Dir.mktmpdir('dab-modern-case-subject') do |directory|
      source_path = File.join(directory, 'invalid.dabm')
      source = "def main()\ncase missing()\nend\nend\n"
      File.binwrite(source_path, source)
      missing_ring = File.join(directory, 'missing.dabcb')
      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )
      stderr = tool_stderr(stderr)

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(stderr).to eq(
        "compiler: #{source_path}:2:5: error: unknown Modern call target \"missing\"\n"
      )
      expect(Dir.children(directory)).to eq(['invalid.dabm'])
    end
  end

  it 'emits deterministic assembly for forward, reversed, and repeated source declaration order' do
    helper = <<~DAB
      def subject():Boolean
      print("subject\\n")
      return true
      end
    DAB
    main = <<~DAB
      def main()
      case subject()
      end
      print("after\\n")
      end
    DAB

    Dir.mktmpdir('dab-modern-case-determinism') do |directory|
      lower_ring = build_stdlib(directory)
      assemblies = [helper + main, main + helper, helper + main].each_with_index.map do |source, index|
        compile_source(source, directory, lower_ring, "case-order-#{index}")
      end

      expect(assemblies.uniq.length).to eq(1)
      main_assembly = assemblies.fetch(0).match(/Fmain:.*?__Fmain_END:/m).to_s
      expect(main_assembly.scan(%r{/\* subject\s+\*/\s+CALL RNIL, S\d+}).length).to eq(1)
      expect(main_assembly).to match(%r{/\* subject\s+\*/\s+CALL RNIL, S\d+.*?/\* PRINT\s+\*/\s+SYSCALL RNIL}m)
      expect(main_assembly).not_to include('JMP', 'JMP_IF', 'CAST')
    end
  end
end

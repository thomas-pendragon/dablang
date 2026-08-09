require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern fixed local reassignment diagnostics' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'fixed-local-reassignment.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
  end

  def parse(source)
    DabModernBootstrapParser.new(source.b, source_unit: source_unit).parse
  end

  def invoke(*command)
    environment = {'BUNDLE_USER_HOME' => File.join(Dir.tmpdir, 'dablang-bundler')}
    Open3.capture3(environment, *command, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(
      "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
    )
  end

  def expect_parse_error(source, message, offending, occurrence: :last, offset: nil)
    expect do
      parse(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(message)
      start_offset = offset || (occurrence == :first ? source.index(offending) : source.rindex(offending))
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [start_offset, start_offset + offending.bytesize]
      )
    }
  end

  def fixed_message(name = 'value')
    %(cannot reassign Modern let binding "#{name}")
  end

  it 'rejects complete writes to typed and untyped lets for every existing literal kind at the full target' do
    literals = %w[nil true false 1] + ['"changed"']
    literals.each do |literal|
      source = "def main()\nlet value = \"fixed\"\nvalue = #{literal}\nend\n"
      expect_parse_error(source, fixed_message, 'value')
    end

    typed = "def main()\nlet value : String = \"fixed\"\nvalue = 1\nend\n"
    expect_parse_error(typed, fixed_message, 'value')
  end

  it 'shares reassignment whitespace and separator structure while preserving direct-call precedence' do
    variants = [
      "def main()\nlet value = 1\nvalue=2\nend\n",
      "def main()\nlet value = 1\nvalue\t =\t 2;end\n",
      "def main()\nlet value = 1\nvalue = 2# separator\nend\n",
    ]
    variants.each { |source| expect_parse_error(source, fixed_message, 'value') }

    source = <<~DAB
      def value()
      end
      def main()
      let value = 1
      value ()
      var mutable = "first"
      mutable = "second"
      print(mutable)
      end
    DAB
    functions = parse(source).lower_into(DabNodeUnit.new)
    main = functions.fetch(1)
    calls = main.blocks[0].all_nodes(DabNodeCall)
    setters = main.blocks[0].all_nodes(DabNodeSetLocalVar).reject do |node|
      node.is_a?(DabNodeDefineLocalVar)
    end

    expect(calls.map(&:real_identifier)).to eq(%w[value print])
    expect(setters.map(&:real_identifier)).to eq(['mutable'])
  end

  it 'keeps equality, annotations, unknown names, and nonlocal targets on their generic boundaries' do
    generic_targets = {
      'adjacent equality' => ["def main()\nlet value = 1\nvalue == 2\nend\n", 'value'],
      'annotation' => ["def main()\nlet value = 1\nvalue : String = 2\nend\n", 'value'],
      'unknown' => ["def main()\nunknown = 2\nend\n", 'unknown'],
      'read before' => ["def main()\nvalue = 2\nlet value = 1\nend\n", 'value'],
      'parameter' => ["def main(value:Fixnum)\nvalue = 2\nend\n", 'value'],
      'callable only' => ["def value()\nend\ndef main()\nvalue = 2\nend\n", 'value'],
      'standalone local' => ["def main()\nlet value = 1\nvalue\nend\n", 'value'],
    }
    generic_targets.each do |description, (source, target)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(target), description
      }
    end

    cross_function = "def first()\nlet value = 1\nend\ndef second()\nvalue = 2\nend\n"
    expect_parse_error(
      cross_function,
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      'value'
    )

    spaced_equality = "def main()\nlet value = 1\nvalue = = 2\nend\n"
    expect_parse_error(
      spaced_equality,
      DabModernBootstrapParseError::GENERIC_MESSAGE,
      '='
    )
  end

  it 'keeps nonliteral and broader right-hand values generic at the first unsupported token' do
    cases = {
      'local' => ["def main()\nlet value = 1\nvalue = other\nend\n", 'other'],
      'call' => ["def main()\nlet value = 1\nvalue = make()\nend\n", 'make'],
      'member' => ["def main()\nlet value = 1\nvalue = 1.length\nend\n", '.'],
    }
    cases.each do |description, (source, offending)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
        expect(source.byteslice(error.source_span.start_offset...error.source_span.end_offset)).to eq(offending), description
      }
    end
  end

  it 'uses existing missing-value, separator, EOF, and CR diagnostics before fixedness' do
    missing_values = {
      "def main()\nlet value = 1\nvalue =\nend\n" => "\n",
      "def main()\nlet value = 1\nvalue =;end\n" => ';',
      "def main()\nlet value = 1\nvalue =# missing\nend\n" => '# missing',
    }
    missing_values.each do |source, offending|
      value_start = source.rindex('value =')
      expect_parse_error(
        source,
        DabModernBootstrapParser::EXPECT_REASSIGNMENT_VALUE_MESSAGE,
        offending,
        offset: source.index(offending, value_start + 'value ='.length)
      )
    end

    eof_source = "def main()\nlet value = 1\nvalue ="
    expect do
      parse(eof_source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_REASSIGNMENT_VALUE_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [eof_source.bytesize, eof_source.bytesize]
      )
    }

    separator = "def main()\nlet value = 1\nvalue = 2 \nend\n"
    expect_parse_error(
      separator,
      DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE,
      ' ',
      offset: separator.index(' ', separator.index('value = 2') + 'value = 2'.length)
    )

    extra_token = "def main()\nlet value = 1\nvalue = 2true\nend\n"
    expect_parse_error(
      extra_token,
      DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE,
      'true'
    )

    separator_eof = "def main()\nlet value = 1\nvalue = 2"
    expect do
      parse(separator_eof)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParser::EXPECT_REASSIGNMENT_SEPARATOR_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [separator_eof.bytesize, separator_eof.bytesize]
      )
    }

    ["\r", "\r\n"].each do |ending|
      source = "def main()\nlet value = 1\nvalue = 2#{ending}end\n"
      expect_parse_error(
        source,
        DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        ending
      )
    end
  end

  it 'finishes structural parsing before source-ordered local preflight' do
    later_structure = <<~DAB
      def main()
      let value = 1
      value = 2
      print(,)
      end
    DAB
    expect do
      parse(later_structure)
    end.to raise_error(
      DabModernBootstrapParseError,
      DabModernBootstrapParser::EXPECT_CALL_ARGUMENT_OR_CLOSE_MESSAGE
    )

    duplicate_first = <<~DAB
      def main()
      let value = 1
      let value = 2
      value = 3
      end
    DAB
    duplicate_target = duplicate_first.index('value', duplicate_first.index('value') + 1)
    expect_parse_error(
      duplicate_first,
      'duplicate Modern local binding "value"',
      'value',
      offset: duplicate_target
    )

    fixed_first = <<~DAB
      def main()
      let value = 1
      value = 2
      let value = 3
      missing()
      end
    DAB
    target = fixed_first.index('value', fixed_first.index('value') + 1)
    expect do
      parse(fixed_first)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(fixed_message)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq([target, target + 5])
    }
  end

  it 'reports fixedness before typed-RHS compatibility and before lower-Ring I/O' do
    source = "def main()\nlet value : String = \"fixed\"\nvalue = 1\nend\n"
    expect_parse_error(source, fixed_message, 'value')

    Dir.mktmpdir('dab-modern-fixed-local-preflight') do |directory|
      source_path = File.join(directory, 'fixed-write.dabm')
      File.binwrite(source_path, source)
      missing_ring = File.join(directory, 'missing.dabcb')
      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:3:0: error: #{fixed_message}\n"
      )
      expect(File).not_to exist(missing_ring)
    end
  end

  it 'emits one exact source-attributed fixture diagnostic and no partial assembly' do
    fixture_path = File.join(
      root,
      'test/modern_source/0066_local_reassignment_remains_unsupported.dabmtest'
    )
    content = File.binread(fixture_path).gsub("\r\n", "\n")
    source, remainder = content.split("## SCHEMA VERSION\n", 2)
    expect(source).to eq(
      "## SOURCE\ndef main()\nlet value = \"fixed\"\nvalue = \"changed\"\nend\n"
    )
    expect(remainder).to eq(
      "1\n## STATUS\n2\n## STDERR\n" \
      'compiler: 0066_local_reassignment_remains_unsupported.dabm:3:0: error: ' \
      "#{fixed_message}\n"
    )

    Dir.mktmpdir('dab-modern-fixed-local-fixture') do |directory|
      source_path = File.join(directory, '0066_local_reassignment_remains_unsupported.dabm')
      File.binwrite(source_path, source.delete_prefix("## SOURCE\n"))
      missing_ring = File.join(directory, 'missing.dabcb')
      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        source_path,
        "--ring-base[]=#{missing_ring}"
      )

      expect([status.exitstatus, stdout]).to eq([2, ''])
      expect(tool_stderr(stderr)).to eq(
        "compiler: #{source_path}:3:0: error: #{fixed_message}\n"
      )
      expect(stderr.lines.grep(/: error: /).length).to eq(1)
      expect(File).not_to exist(missing_ring)
    end
  end
end

require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'Modern function-body indentation' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:source_unit) do
    DabSourceUnit.new(
      input: 'body-indentation.dabm',
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

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq([0, "PASS #{artifact}\n", ''])
    artifact
  end

  def compile(directory, basename, source, lower)
    path = File.join(directory, "#{basename}.dabm")
    File.binwrite(path, source)
    stdout, stderr, status = invoke(RbConfig.ruby, compiler, path, "--ring-base[]=#{lower}")
    [stdout, tool_stderr(stderr), status, path]
  end

  it 'accepts ASCII spaces on every LF-started body line and omits them from lowering' do
    source = [
      "def main()\n",
      "  # first comment\n",
      "   \n",
      "  print(\"one\")\n",
      "    nil\n",
      "  // later comment\n",
      " print(\"two\")\n",
      "   end\n",
    ].join

    declaration = parse(source).declarations.fetch(0)
    expect(declaration.body_items.map(&:kind)).to eq(%i[direct_call nil direct_call])

    function = declaration.lower_into(DabNodeUnit.new)
    source_parts = function.all_nodes.flat_map(&:source_parts)
    expect(source_parts.map(&:to_s)).not_to include(' ', '  ', '   ', '    ')
    expect(function.blocks[0].all_nodes(DabNodeCall).map(&:real_identifier)).to eq(%w[print print])
  end

  it 'keeps indentation assembly-neutral and deterministic in both declaration orders' do
    forward = "def emit()\n  print(\"hello\\n\")\nend\n\ndef main()\n  emit()\nend\n"
    reverse = "def main()\n    emit()\nend\ndef emit()\n print(\"hello\\n\")\nend\n"
    unindented = "def emit()\nprint(\"hello\\n\")\nend\n\ndef main()\nemit()\nend\n"

    Dir.mktmpdir('dab-modern-body-indentation') do |directory|
      lower = build_stdlib(directory)
      results = {
        forward: compile(directory, 'forward', forward, lower),
        reverse: compile(directory, 'reverse', reverse, lower),
        unindented: compile(directory, 'unindented', unindented, lower),
      }

      results.each do |description, (stdout, stderr, status, _path)|
        expect([status.exitstatus, stderr]).to eq([0, '']), description.to_s
        expect(stdout).to include('Femit:', 'Fmain:'), description.to_s
      end
      expect(results[:reverse].fetch(0)).to eq(results[:forward].fetch(0))
      expect(results[:unindented].fetch(0)).to eq(results[:forward].fetch(0))
    end
  end

  it 'rejects every adjacent whitespace near miss at its first unsupported token' do
    cases = {
      'TAB first body line' => ["def main()\n\tprint()\nend\n", 11, DabModernBootstrapParseError::GENERIC_MESSAGE],
      'TAB later body line' => ["def main()\nprint()\n\tend\n", 19, DabModernBootstrapParseError::GENERIC_MESSAGE],
      'top-level spaces' => ["  def main()\nend\n", 0, DabModernBootstrapParseError::GENERIC_MESSAGE],
      'same-line header semicolon spaces' => ["def main(); print()\nend\n", 11, DabModernBootstrapParseError::GENERIC_MESSAGE],
      'same-line body semicolon spaces' => ["def main()\nprint(); print()\nend\n", 19, DabModernBootstrapParseError::GENERIC_MESSAGE],
      'trailing spaces' => ["def main()\nprint()  \nend\n", 18, DabModernBootstrapParser::EXPECT_CALL_BODY_SEPARATOR_MESSAGE],
      'indented semicolon' => ["def main()\n  ;print()\nend\n", 13, DabModernBootstrapParseError::GENERIC_MESSAGE],
    }

    cases.each do |description, (source, offset, message)|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(message), description
        expect(error.source_span.start_offset).to eq(offset), description
      }
    end
  end

  it 'preserves CR diagnostics and moves deferred indented syntax to its real token' do
    ["def main()\n  \rend\n", "def main()\n  \r\nend\n"].each do |source|
      expect do
        parse(source)
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE)
        expect(error.source_span.start_offset).to eq(source.index("\r"))
      }
    end

    source = "def main()\n  return nil\nend\n"
    expect do
      parse(source)
    end.to raise_error(DabModernBootstrapParseError) { |error|
      expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE)
      expect([error.source_span.start_offset, error.source_span.end_offset]).to eq(
        [source.index('return'), source.index('return') + 6]
      )
    }
  end
end

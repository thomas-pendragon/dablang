require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'set'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'

describe 'minimal Modern main bootstrap' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:source_path) { File.join(root, 'test/modern_minimal_main/program.dabm') }
  let(:compiler) { File.join(root, 'src/compiler/compiler.rb') }
  let(:assembler) { File.join(root, 'src/tobinary/tobinary.rb') }
  let(:stdlib_frontend) { File.join(root, 'src/frontend/frontend_stdlib.rb') }
  let(:vm) { File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}") }
  let(:clipboard_fallback) do
    "clipboard: Could not find required program xsl or xclip (X11) or wl-clipboard (Wayland)\n" \
      "Using file-based (fake) clipboard\n"
  end
  let(:near_misses) do
    {
      'empty name' => ["def \nend\n".b, {offset: 4, line: 2, column: 0}],
      'body content' => ["def main\nvalue\nend\n".b, {offset: 9, line: 2, column: 0}],
      'leading token' => [" def main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'trailing token' => ["def main\nend\nextra\n".b, {offset: 13, line: 3, column: 0}],
      'missing end' => ["def main\n".b, {offset: 9, line: 2, column: 0}],
      'incomplete def' => ['de'.b, {offset: 0, line: 1, column: 0}],
      'incomplete end' => ["def main\nen\n".b, {offset: 9, line: 2, column: 0}],
      'CR-only' => ["def main\rend\r".b, {offset: 8, line: 1, column: 8}],
      'CRLF' => ["def main\r\nend\r\n".b, {offset: 8, line: 1, column: 8}],
      'missing final LF' => ["def main\nend".b, {offset: 12, line: 2, column: 3}],
      'NUL body' => ["def main\n\0\nend\n".b, {offset: 9, line: 2, column: 0}],
    }
  end
  let(:lf_separator_declarations) do
    [
      "def main\nend\n".b,
      "\ndef main\nend\n".b,
      "def main\n\nend\n".b,
      "def main\nend\n\n".b,
      "\n\ndef main\n\n\nend\n\n".b,
    ]
  end
  let(:semicolon_separator_declarations) do
    [
      'def main;end;'.b,
      ";def main\nend\n".b,
      "def main\n;end\n".b,
      "def main\nend\n;".b,
      ';;;def main;;;end;;;'.b,
      ";\n;def main\n;;\nend;\n;".b,
    ]
  end
  let(:separator_only_sources) do
    [''.b, "\n".b, "\n\n\n".b, ';'.b, ';;;'.b, ";\n;;\n".b]
  end
  let(:comment_declarations) do
    [
      "# leading\ndef main\nend\n".b,
      "// leading\ndef main\nend\n".b,
      "# leading // ;\ndef main# header // ;\n// body # ;\nend# trailing // ;".b,
      "// leading # ;\ndef main// header # ;\n# body // ;\nend// trailing # ;".b,
      "# arbitrary // ;\0\r\t\xff bytes\ndef main;# body // ;\0\r\t\x80\nend;".b,
    ]
  end
  let(:comment_only_sources) do
    [
      '# comment at EOF'.b,
      '// comment at EOF'.b,
      "# first\n// second\n".b,
      ";# first\n;// second\n;".b,
    ]
  end
  let(:separator_near_misses) do
    {
      'newline inside the declaration header' => ["def\nmain\nend\n".b, {offset: 3, line: 2, column: 0}],
      'space-only body line' => ["def main\n \nend\n".b, {offset: 9, line: 2, column: 0}],
      'body content after separators' => ["def main\n\nvalue\nend\n".b, {offset: 10, line: 3, column: 0}],
      'CRLF separators' => ["def main\r\nend\r\n".b, {offset: 8, line: 1, column: 8}],
    }
  end
  let(:semicolon_near_misses) do
    {
      'inside the def keyword' => ["de;f main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'between def and its required space' => ["def;main\nend\n".b, {offset: 3, line: 1, column: 3}],
      'semicolon after a shorter callable name' => ["def ma;in\nend\n".b, {offset: 7, line: 1, column: 7}],
      'inside the end keyword' => ["def main\nen;d\n".b, {offset: 9, line: 2, column: 0}],
      'between body identifier fragments' => ["def main;va;lue\nend;".b, {offset: 9, line: 1, column: 9}],
    }
  end
  let(:comment_near_misses) do
    {
      'single slash' => ["/ comment\ndef main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'hash embedded in def' => ["de# split\nf main\nend\n".b, {offset: 0, line: 1, column: 0}],
      'comment after a shorter callable name' => ["def ma// split\nin\nend\n".b, {offset: 15, line: 2, column: 0}],
      'slash before a hash' => ["def main/# comment\nend\n".b, {offset: 8, line: 1, column: 8}],
      'body statement after a comment' => ["def main\n# body\nvalue\nend\n".b, {offset: 16, line: 3, column: 0}],
      'CR before a comment marker' => ["def main\r# comment\nend\n".b, {offset: 8, line: 1, column: 8}],
      'CRLF before a comment marker' => ["def main\r\n# comment\nend\r\n".b, {offset: 8, line: 1, column: 8}],
    }
  end
  let(:structural_diagnostic_cases) do
    {
      'space after def at EOF' => {
        source: 'def'.b,
        message: DabModernBootstrapParser::EXPECT_SPACE_MESSAGE,
        span: [3, 3],
        location: {offset: 3, line: 1, column: 3},
      },
      'space after def before LF' => {
        source: "def\n".b,
        message: DabModernBootstrapParser::EXPECT_SPACE_MESSAGE,
        span: [3, 4],
        location: {offset: 3, line: 2, column: 0},
      },
      'main after def-space at EOF' => {
        source: 'def '.b,
        message: DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE,
        span: [4, 4],
        location: {offset: 4, line: 1, column: 4},
      },
      'main after def-space before LF' => {
        source: "def \n".b,
        message: DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE,
        span: [4, 5],
        location: {offset: 4, line: 2, column: 0},
      },
      'separator after main at EOF' => {
        source: 'def main'.b,
        message: DabModernBootstrapParser::EXPECT_NAME_SEPARATOR_MESSAGE,
        span: [8, 8],
        location: {offset: 8, line: 1, column: 8},
      },
      'separator after main before a literal' => {
        source: "def main\"body\"\nend\n".b,
        message: DabModernBootstrapParser::EXPECT_NAME_SEPARATOR_MESSAGE,
        span: [8, 14],
        location: {offset: 8, line: 1, column: 8},
      },
      'separator after main before a spaced end' => {
        source: "def main end\n".b,
        message: DabModernBootstrapParser::EXPECT_NAME_SEPARATOR_MESSAGE,
        span: [8, 9],
        location: {offset: 8, line: 1, column: 8},
      },
      'separator after literal at EOF' => {
        source: "def main\nnil".b,
        message: DabModernBootstrapParser::EXPECT_LITERAL_SEPARATOR_MESSAGE,
        span: [12, 12],
        location: {offset: 12, line: 2, column: 3},
      },
      'separator after literal before end' => {
        source: "def main\n1end\n".b,
        message: DabModernBootstrapParser::EXPECT_LITERAL_SEPARATOR_MESSAGE,
        span: [10, 13],
        location: {offset: 10, line: 2, column: 1},
      },
      'separator after literal before a spaced end' => {
        source: "def main\nnil end\n".b,
        message: DabModernBootstrapParser::EXPECT_LITERAL_SEPARATOR_MESSAGE,
        span: [12, 13],
        location: {offset: 12, line: 2, column: 3},
      },
      'closing end at EOF' => {
        source: "def main\n".b,
        message: DabModernBootstrapParser::EXPECT_END_MESSAGE,
        span: [9, 9],
        location: {offset: 9, line: 2, column: 0},
      },
      'closing end after consumed separators and comment' => {
        source: "def main\nnil\n# missing".b,
        message: DabModernBootstrapParser::EXPECT_END_MESSAGE,
        span: [22, 22],
        location: {offset: 22, line: 3, column: 9},
      },
      'separator after closing end at EOF' => {
        source: "def main\nend".b,
        message: DabModernBootstrapParser::EXPECT_END_SEPARATOR_MESSAGE,
        span: [12, 12],
        location: {offset: 12, line: 2, column: 3},
      },
      'separator after closing end before a token' => {
        source: "def main\nend\"x\"".b,
        message: DabModernBootstrapParser::EXPECT_END_SEPARATOR_MESSAGE,
        span: [12, 15],
        location: {offset: 12, line: 2, column: 3},
      },
      'leading end' => {
        source: "end\n".b,
        message: DabModernBootstrapParser::UNEXPECTED_END_MESSAGE,
        span: [0, 3],
        location: {offset: 0, line: 1, column: 0},
      },
      'extra end' => {
        source: "def main\nend\nend\n".b,
        message: DabModernBootstrapParser::UNEXPECTED_END_MESSAGE,
        span: [13, 16],
        location: {offset: 13, line: 3, column: 0},
      },
      'lone CR separator' => {
        source: "def main\rend\r".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [8, 9],
        location: {offset: 8, line: 1, column: 8},
      },
      'CRLF separator' => {
        source: "def main\r\nend\r\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [8, 10],
        location: {offset: 8, line: 1, column: 8},
      },
      'lone CR after spaces following main' => {
        source: "def main \rend\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [9, 10],
        location: {offset: 9, line: 1, column: 9},
      },
      'CRLF after spaces following main' => {
        source: "def main \r\nend\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [9, 11],
        location: {offset: 9, line: 1, column: 9},
      },
      'lone CR after spaces following literal' => {
        source: "def main\nnil \rend\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [13, 14],
        location: {offset: 13, line: 2, column: 4},
      },
      'CRLF after spaces following literal' => {
        source: "def main\nnil \r\nend\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [13, 15],
        location: {offset: 13, line: 2, column: 4},
      },
      'lone CR after spaces following end' => {
        source: "def main\nend \r".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [13, 14],
        location: {offset: 13, line: 2, column: 4},
      },
      'CRLF after spaces following end' => {
        source: "def main\nend \r\n".b,
        message: DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
        span: [13, 15],
        location: {offset: 13, line: 2, column: 4},
      },
    }
  end

  def invoke(*command, input: nil)
    Open3.capture3(*command, stdin_data: input, chdir: root)
  end

  def tool_stderr(stderr)
    stderr.delete_prefix(clipboard_fallback)
  end

  def expected_rejection_message(description)
    structural = {
      'empty name' => DabModernBootstrapParser::EXPECT_CALLABLE_NAME_MESSAGE,
      'missing end' => DabModernBootstrapParser::EXPECT_END_MESSAGE,
      'CR-only' => DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      'CRLF' => DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      'missing final LF' => DabModernBootstrapParser::EXPECT_END_SEPARATOR_MESSAGE,
      'newline inside the declaration header' => DabModernBootstrapParser::EXPECT_SPACE_MESSAGE,
      'CRLF separators' => DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      'between def and its required space' => DabModernBootstrapParser::EXPECT_SPACE_MESSAGE,
      'CR before a comment marker' => DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
      'CRLF before a comment marker' => DabModernBootstrapParser::INVALID_CR_SEPARATOR_MESSAGE,
    }
    structural.fetch(description, DabModernBootstrapParseError::GENERIC_MESSAGE)
  end

  def build_stdlib(directory)
    artifact = File.join(directory, 'stdlib.dabcb')
    stdout, stderr, status = invoke(RbConfig.ruby, stdlib_frontend, "--output=#{artifact}")
    expect([status.exitstatus, stdout]).to eq [0, "PASS #{artifact}\n"]
    expect(tool_stderr(stderr)).not_to include('exception:', 'FAILED')
    artifact
  end

  def compile_application(directory, lower:, basename: 'application')
    assembly, stderr, status = invoke(
      RbConfig.ruby,
      compiler,
      source_path,
      "--ring-base[]=#{lower}"
    )
    expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']

    bytecode, assembler_stderr, assembler_status = invoke(
      RbConfig.ruby,
      assembler,
      input: assembly
    )
    expect([assembler_status.exitstatus, tool_stderr(assembler_stderr)]).to eq [0, '']
    artifact = File.join(directory, "#{basename}.dabcb")
    File.binwrite(artifact, bytecode)
    {assembly: assembly, artifact: artifact, bytecode: bytecode}
  end

  def parse_pipeline(lower, upper)
    reader = DabBinReader.new
    lower_data = reader.parse_dab_binary(File.binread(lower), [])
    upper_data = reader.parse_dab_binary(File.binread(upper), lower_data.fetch(:all_symbols))
    [lower_data, upper_data]
  end

  def run_vm(directory, inputs, basename:)
    application_stdout = File.join(directory, "#{basename}.application-stdout")
    process_stdout, host_stderr, status = invoke(vm, "--out=#{application_stdout}", *inputs)
    {
      status: status.exitstatus,
      process_stdout: process_stdout,
      application_stdout: File.binread(application_stdout),
      host_stderr: host_stderr,
    }
  end

  def artifact_diagnostic_patterns(data, seen_classes)
    header = data.fetch(:header)
    address = '(?:0x)?[0-9a-fA-F]+'
    patterns = [
      /^vm: newformat: h: #{header.fetch(:size_of_header)}, d: #{header.fetch(:size_of_data)}, s: #{header.fetch(:sections_count)}$/,
      /^vm: offset is #{header.fetch(:offset)}$/,
    ]
    header.fetch(:sections).each_with_index do |section, index|
      absolute_address = header.fetch(:offset) + section.fetch(:address)
      patterns << /^vm: newformat: section #{index}: name '#{Regexp.escape(section.fetch(:name))}' address #{address}\/#{absolute_address} length #{section.fetch(:length)}$/
    end

    symbol_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'symb' }
    patterns << /^readbin: #{symbol_section.fetch(:length) / 8} symbol\(s\) to read$/ if symbol_section

    class_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'clas' }
    if class_section
      patterns << /^classad=#{address}$/
      data.fetch(:klasses).each do |klass|
        patterns << /^\[class\] index=#{klass.fetch(:index)} parent=#{klass.fetch(:parent_index)} symbol=\d+ template=0$/
        next if seen_classes.include?(klass.fetch(:index))

        parent = STANDARD_CLASSES_MAP.fetch(klass.fetch(:parent_index))
        patterns << /^vm: add class <#{Regexp.escape(klass.fetch(:symbol))}> \(parent = <#{Regexp.escape(parent)}>\)\.$/
        seen_classes << klass.fetch(:index)
      end
    end

    data.fetch(:functions).each do |function|
      patterns << /^vm: add function <#{Regexp.escape(function.fetch(:symbol))}>\.$/
    end
    code_section = header.fetch(:sections).find { |section| section.fetch(:name) == 'code' }
    code_address = header.fetch(:offset) + code_section.fetch(:address)
    patterns << /^vm: seek initial code pointer to #{code_address}$/
    patterns
  end

  def expect_success_host_diagnostics(stderr, lower_data, upper_data)
    seen_classes = STANDARD_CLASSES_MAP.keys.to_set
    patterns = [
      /^vm: predefine default classes$/,
      /^VM options: autorun yes raw no cov no$/,
      *artifact_diagnostic_patterns(lower_data, seen_classes),
      *artifact_diagnostic_patterns(upper_data, seen_classes),
      /^vm: define defaults$/,
      /^vm: define default classes$/,
      /^vm: define default functions$/,
      /^vm: trying to initialize attributes$/,
      /^vm: initialize attributes \(__init_0\)$/,
      /^vm: initialize attributes \(__init_\d+\)$/,
      /^vm: VM destroyed!$/,
      /^vm: reset \$VM pointer$/,
    ]
    lines = stderr.lines(chomp: true)

    expect(stderr).not_to match(/error|failed|sanitizer|warning/i)
    expect(lines.length).to eq(patterns.length)
    lines.zip(patterns).each_with_index do |(line, pattern), index|
      expect(line).to match(pattern), "unexpected VM host diagnostic line #{index + 1}: #{line.inspect}"
    end
  end

  it 'parses exactly one empty no-argument main declaration into the existing typed AST boundary' do
    source_unit = DabSourceUnit.new(
      input: source_path,
      syntax_profile: DabSyntaxProfile::MODERN
    )
    declaration = DabModernBootstrapParser.new(File.binread(source_path), source_unit: source_unit).parse
    unit = DabNodeUnit.new

    function = declaration.lower_into(unit)

    expect(declaration.source_unit).to equal(source_unit)
    expect(function).to be_a(DabNodeFunction)
    expect(function.identifier).to eq 'main'
    expect(function.arglist).to be_empty
    expect(function.blocks[0]).to be_empty
    expect(unit.has_function?('main')).to equal(function)
  end

  it 'treats LF runs as separators around the existing empty main declaration' do
    source_unit = DabSourceUnit.new(
      input: 'separator-main.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    lf_separator_declarations.each do |source|
      declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      unit = DabNodeUnit.new
      function = declaration.lower_into(unit)

      expect(function.identifier).to eq 'main'
      expect(function.arglist).to be_empty
      expect(function.blocks[0]).to be_empty
      expect(unit.has_function?('main')).to equal(function)
    end
  end

  it 'treats semicolon and mixed runs as separators only at existing separator positions' do
    source_unit = DabSourceUnit.new(
      input: 'semicolon-separator-main.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    semicolon_separator_declarations.each do |source|
      declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      unit = DabNodeUnit.new
      function = declaration.lower_into(unit)

      expect(function.identifier).to eq 'main'
      expect(function.arglist).to be_empty
      expect(function.blocks[0]).to be_empty
      expect(unit.has_function?('main')).to equal(function)
    end
  end

  it 'treats both exact line-comment markers equivalently within existing separator runs' do
    source_unit = DabSourceUnit.new(
      input: 'comment-separator-main.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    comment_declarations.each do |source|
      declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      unit = DabNodeUnit.new
      function = declaration.lower_into(unit)

      expect(function.identifier).to eq 'main'
      expect(function.arglist).to be_empty
      expect(function.blocks[0]).to be_empty
      expect(unit.has_function?('main')).to equal(function)
    end
  end

  it 'treats an LF-only source as the existing empty Modern upper unit' do
    source_unit = DabSourceUnit.new(
      input: 'separator-only.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    expect(DabModernBootstrapParser.new("\n".b, source_unit: source_unit).parse).to be_nil
    expect(DabModernBootstrapParser.new("\n\n\n".b, source_unit: source_unit).parse).to be_nil
  end

  it 'treats semicolon-only and mixed separator sources as the existing empty Modern upper unit' do
    source_unit = DabSourceUnit.new(
      input: 'semicolon-separator-only.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    separator_only_sources.drop(3).each do |source|
      expect(DabModernBootstrapParser.new(source, source_unit: source_unit).parse).to be_nil
    end
  end

  it 'treats comment-only and comment/separator sources as the existing empty Modern upper unit' do
    source_unit = DabSourceUnit.new(
      input: 'comment-separator-only.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    comment_only_sources.each do |source|
      expect(DabModernBootstrapParser.new(source, source_unit: source_unit).parse).to be_nil
    end
  end

  it 'retains exact scanner locations while skipping separator runs' do
    source = "\n\ndef main\n\nend\n\n".b
    source_unit = DabSourceUnit.new(
      input: 'separator-locations.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse

    expect(declaration.source_unit).to equal(source_unit)
    expect(declaration.source_span.start_location.to_h).to eq(offset: 2, line: 3, column: 0)
    expect(declaration.source_span.end_location.to_h).to eq(offset: 16, line: 7, column: 0)
  end

  it 'keeps every LF as an individually located scanner token' do
    source = "\ndef main\n\nend\n\n".b
    source_unit = DabSourceUnit.new(
      input: 'separator-tokens.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    expect(tokens.map(&:kind)).to eq(
      %i[line_feed def space identifier line_feed line_feed end line_feed line_feed eof]
    )
    expect(tokens.select { |token| token.kind == :line_feed }.map { |token| token.source_location.to_h }).to eq(
      [
        {offset: 0, line: 2, column: 0},
        {offset: 9, line: 3, column: 0},
        {offset: 10, line: 4, column: 0},
        {offset: 14, line: 5, column: 0},
        {offset: 15, line: 6, column: 0},
      ]
    )
    expect(tokens).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'keeps semicolon as syntax with exact locations while only LF advances the line' do
    source = ";\ndef main;\n;end;\n;".b
    source_unit = DabSourceUnit.new(
      input: 'semicolon-separator-tokens.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    expect(tokens.map(&:kind)).to eq(
      %i[semicolon line_feed def space identifier semicolon line_feed semicolon end semicolon line_feed semicolon eof]
    )
    semicolons = tokens.select { |token| token.kind == :semicolon }
    expect(semicolons.map { |token| token.source_location.to_h }).to eq(
      [
        {offset: 0, line: 1, column: 0},
        {offset: 10, line: 2, column: 8},
        {offset: 12, line: 3, column: 0},
        {offset: 16, line: 3, column: 4},
        {offset: 18, line: 4, column: 0},
      ]
    )
    expect(semicolons.map { |token| [token.text, token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[';', 0, 1], [';', 10, 11], [';', 12, 13], [';', 16, 17], [';', 18, 19]]
    )
    expect(tokens).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'keeps surrounding separator runs outside a semicolon-framed declaration span' do
    source_unit = DabSourceUnit.new(
      input: 'semicolon-separator-span.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    declaration = DabModernBootstrapParser.new(';def main;end;;'.b, source_unit: source_unit).parse

    expect(declaration.source_span.start_location.to_h).to eq(offset: 1, line: 1, column: 1)
    expect(declaration.source_span.end_location.to_h).to eq(offset: 14, line: 1, column: 14)
  end

  it 'keeps comment bodies and LF boundaries as exact, separate scanner tokens' do
    source = "#a//;\0\r\t\xff\n//#;a\0\r\t\x80\n".b
    source_unit = DabSourceUnit.new(
      input: 'comment-tokens.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    scanner = DabModernBootstrapScanner.new(source, source_unit: source_unit)
    tokens = []
    loop do
      token = scanner.next_token
      tokens << token
      break if token.kind == :eof
    end

    expect(tokens.map(&:kind)).to eq(%i[line_comment line_feed line_comment line_feed eof])
    expect(tokens.map(&:text)).to eq(["#a//;\0\r\t\xff".b, "\n".b, "//#;a\0\r\t\x80".b, "\n".b, ''.b])
    expect(tokens.map { |token| [token.source_span.start_offset, token.source_span.end_offset] }).to eq(
      [[0, 9], [9, 10], [10, 19], [19, 20], [20, 20]]
    )
    expect(tokens.map { |token| token.source_location.to_h }).to eq(
      [
        {offset: 0, line: 1, column: 0},
        {offset: 9, line: 2, column: 0},
        {offset: 10, line: 2, column: 0},
        {offset: 19, line: 3, column: 0},
        {offset: 20, line: 3, column: 0},
      ]
    )
    expect(tokens.map { |token| token.source_span.end_location.to_h }).to eq(
      [
        {offset: 9, line: 2, column: 0},
        {offset: 10, line: 2, column: 0},
        {offset: 19, line: 3, column: 0},
        {offset: 20, line: 3, column: 0},
        {offset: 20, line: 3, column: 0},
      ]
    )
    expect(tokens).to all(satisfy { |token| token.source_span.source_unit.equal?(source_unit) })
  end

  it 'ends a declaration span after an EOF-terminated trailing comment' do
    source = "# lead\n;def main// header\n# body\n;end# tail".b
    source_unit = DabSourceUnit.new(
      input: 'comment-separator-span.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    declaration = DabModernBootstrapParser.new(source, source_unit: source_unit).parse

    expect(declaration.source_span.start_location.to_h).to eq(offset: 8, line: 2, column: 1)
    expect(declaration.source_span.end_location.to_h).to eq(offset: 43, line: 4, column: 10)
  end

  it 'reports the eight recognized-main diagnostics with exact scanner or zero-width EOF spans' do
    source_unit = DabSourceUnit.new(
      input: 'structural-diagnostic.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    structural_diagnostic_cases.each do |description, test_case|
      expect do
        DabModernBootstrapParser.new(test_case.fetch(:source), source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(test_case.fetch(:message)), description
        expect([error.source_span.start_offset, error.source_span.end_offset])
          .to eq(test_case.fetch(:span)), description
        expect(error.source_location.to_h).to eq(test_case.fetch(:location)), description
        expect(error.source_span.source_unit).to equal(source_unit)
      }
    end
  end

  it 'keeps deferred header, expression, declaration, and top-level syntax on the generic fallback' do
    source_unit = DabSourceUnit.new(
      input: 'deferred-modern-syntax.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )
    cases = {
      'identifier body' => "def main\nvalue\nend\n".b,
      'operator expression' => "def main\n1+2\nend\n".b,
      'spaced operator expression' => "def main\n1 + 2\nend\n".b,
      'trailing top-level form' => "def main\nend\nextra\n".b,
      'incomplete identifier' => 'de'.b,
      'incomplete expression or end' => "def main\nen\n".b,
    }

    cases.each do |description, source|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(DabModernBootstrapParseError::GENERIC_MESSAGE), description
      }
    end
  end

  it 'rejects non-separator whitespace and later syntax at the first scanner location' do
    source_unit = DabSourceUnit.new(
      input: 'separator-near-miss.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    separator_near_misses.each do |description, (source, location)|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(expected_rejection_message(description))
        expect(error.source_location.to_h).to eq(location), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'rejects semicolons inside header tokens and outside separator positions at the first scanner location' do
    source_unit = DabSourceUnit.new(
      input: 'semicolon-near-miss.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    semicolon_near_misses.each do |description, (source, location)|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(expected_rejection_message(description))
        expect(error.source_location.to_h).to eq(location), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'rejects comment-marker near misses and later syntax at the first scanner location' do
    source_unit = DabSourceUnit.new(
      input: 'comment-near-miss.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    comment_near_misses.each do |description, (source, location)|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(expected_rejection_message(description))
        expect(error.source_location.to_h).to eq(location), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'rejects every excluded bootstrap shape at the first shared-scanner location' do
    source_unit = DabSourceUnit.new(
      input: 'near-miss.dabm',
      syntax_profile: DabSyntaxProfile::MODERN
    )

    near_misses.each do |description, (source, location)|
      expect do
        DabModernBootstrapParser.new(source, source_unit: source_unit).parse
      end.to raise_error(DabModernBootstrapParseError) { |error|
        expect(error.message).to eq(expected_rejection_message(description))
        expect(error.source_location.to_h).to eq(location), description
        expect(error.source_location.source_unit).to equal(source_unit)
      }
    end
  end

  it 'reports exact compiler diagnostics for every near miss over the Legacy stdlib Ring' do
    Dir.mktmpdir('dab-modern-minimal-main-diagnostics') do |directory|
      lower = build_stdlib(directory)

      near_misses.each_with_index do |(description, (source, location)), index|
        path = File.join(directory, sprintf('near-miss-%02d.dabm', index))
        File.binwrite(path, source)
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          path,
          "--ring-base[]=#{lower}"
        )
        expected =
          "compiler: #{path}:#{location.fetch(:line)}:#{location.fetch(:column)}: error: " \
          "#{expected_rejection_message(description)}\n"

        aggregate_failures(description) do
          expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq [2, '', expected]
        end
      end
    end
  end

  it 'reports each structural diagnostic transactionally without changing the lower Ring' do
    representatives = [
      'space after def before LF',
      'main after def-space before LF',
      'separator after main before a literal',
      'separator after literal at EOF',
      'closing end after consumed separators and comment',
      'separator after closing end at EOF',
      'extra end',
      'CRLF after spaces following main',
    ]

    Dir.mktmpdir('dab-modern-structural-diagnostics') do |directory|
      lower = build_stdlib(directory)
      lower_before = File.binread(lower)

      representatives.each_with_index do |description, index|
        test_case = structural_diagnostic_cases.fetch(description)
        path = File.join(directory, sprintf('structural-%02d.dabm', index))
        File.binwrite(path, test_case.fetch(:source))
        stdout, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          path,
          "--ring-base[]=#{lower}"
        )
        location = test_case.fetch(:location)
        expected =
          "compiler: #{path}:#{location.fetch(:line)}:#{location.fetch(:column)}: error: " \
          "#{test_case.fetch(:message)}\n"

        aggregate_failures(description) do
          expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq [2, '', expected]
          expect(File.binread(lower)).to eq(lower_before)
        end
      end
    end
  end

  it 'reports a recognized structural error before loading a missing lower Ring' do
    Dir.mktmpdir('dab-modern-structural-before-ring') do |directory|
      path = File.join(directory, 'missing-end.dabm')
      missing_lower = File.join(directory, 'missing-stdlib.dabcb')
      File.binwrite(path, "def main\n")

      stdout, stderr, status = invoke(
        RbConfig.ruby,
        compiler,
        path,
        "--ring-base[]=#{missing_lower}"
      )
      expected =
        "compiler: #{path}:2:0: error: #{DabModernBootstrapParser::EXPECT_END_MESSAGE}\n"

      expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq [2, '', expected]
      expect(File).not_to exist(missing_lower)
    end
  end

  it 'compiles separator variants to the same Modern upper assembly' do
    Dir.mktmpdir('dab-modern-newline-separators') do |directory|
      lower = build_stdlib(directory)
      assemblies = (lf_separator_declarations + semicolon_separator_declarations + comment_declarations)
                   .each_with_index.map do |source, index|
        path = File.join(directory, "separator-#{index}.dabm")
        File.binwrite(path, source)
        assembly, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          path,
          "--ring-base[]=#{lower}"
        )

        expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']
        assembly
      end

      expect(assemblies.uniq.length).to eq 1

      empty_assemblies = (separator_only_sources + comment_only_sources).each_with_index.map do |source, index|
        path = File.join(directory, "empty-separator-#{index}.dabm")
        File.binwrite(path, source)
        assembly, stderr, status = invoke(
          RbConfig.ruby,
          compiler,
          path,
          "--ring-base[]=#{lower}"
        )

        expect([status.exitstatus, tool_stderr(stderr)]).to eq [0, '']
        expect(assembly).not_to include('Fmain:')
        assembly
      end

      expect(empty_assemblies.uniq.length).to eq 1
    end
  end

  it 'keeps the canonical declaration unsupported without a lower Ring' do
    stdout, stderr, status = invoke(RbConfig.ruby, compiler, source_path)

    expected = [
      2,
      '',
      "compiler: #{source_path}:1:0: error: " \
      "unsupported Dab syntax profile \"modern\": parser is not implemented\n",
    ]
    expect([status.exitstatus, stdout, tool_stderr(stderr)]).to eq expected
  end

  it 'builds and runs two byte-identical Modern upper Rings over separate Legacy stdlib Rings' do
    expect(File).to exist(vm)

    Dir.mktmpdir('dab-modern-minimal-main') do |temporary_root|
      results = Array.new(2) do |index|
        directory = File.join(temporary_root, "run-#{index}")
        Dir.mkdir(directory)
        lower = build_stdlib(directory)
        upper = compile_application(directory, lower: lower)
        lower_data, upper_data = parse_pipeline(lower, upper.fetch(:artifact))
        runtime = run_vm(directory, [lower, upper.fetch(:artifact)], basename: 'success')

        expect(runtime.slice(:status, :process_stdout, :application_stdout)).to eq(
          status: 0,
          process_stdout: '',
          application_stdout: ''
        )
        expect_success_host_diagnostics(runtime.fetch(:host_stderr), lower_data, upper_data)
        expect(upper.fetch(:assembly)).to include(
          'Fmain:',
          'RETURN RNIL',
          'W_METHOD',
          '/* main'
        )
        expect(upper.fetch(:assembly)).not_to include('KERNEL_CALL', 'WARN')

        main = upper_data.fetch(:functions).find { |function| function.fetch(:symbol) == 'main' }
        expect(main).to include(klass: nil, args: [], ret: {klass: 'Object'})
        upper_symbols = ["__init_#{File.size(lower)}", 'main']
        expect(upper_data.fetch(:symbols)).to eq upper_symbols
        expect(upper_data.fetch(:functions).map { |function| function.fetch(:symbol) }).to eq upper_symbols
        expect(upper_data.fetch(:header).fetch(:offset)).to eq File.size(lower)
        expect(main.fetch(:address)).to be > File.size(lower)
        expect(upper_data.fetch(:header).fetch(:sections).map { |section| section.fetch(:name) }).not_to include('data')
        expect(upper.fetch(:bytecode).bytesize).to be < File.size(lower)
        expect(lower_data.fetch(:functions).map { |function| function.fetch(:symbol) }).to include('puts')
        expect(lower_data.fetch(:klasses).map { |klass| klass.fetch(:symbol) }).to include('Set')

        {
          directory: directory,
          lower: lower,
          upper: upper,
          lower_data: lower_data,
          upper_data: upper_data,
          runtime: runtime,
        }
      end

      first, second = results
      expect(File.binread(first.fetch(:lower))).to eq File.binread(second.fetch(:lower))
      expect(first.fetch(:upper).fetch(:bytecode)).to eq second.fetch(:upper).fetch(:bytecode)
      expect(first.fetch(:runtime).fetch(:host_stderr)).to eq second.fetch(:runtime).fetch(:host_stderr)

      removed = run_vm(
        first.fetch(:directory),
        [first.fetch(:upper).fetch(:artifact)],
        basename: 'removed-lower'
      )
      expect(removed.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: 1,
        process_stdout: '',
        application_stdout: ''
      )
      expected_removed_diagnostics = [
        'vm: predefine default classes',
        'VM options: autorun yes raw no cov no',
        'vm: invalid bytecode String/symbol data: symb entry 0 reference is outside the artifact.',
        'vm: VM destroyed!',
        'vm: reset $VM pointer',
      ]
      expect(removed.fetch(:host_stderr).lines(chomp: true)).to eq expected_removed_diagnostics

      reversed = run_vm(
        first.fetch(:directory),
        [first.fetch(:upper).fetch(:artifact), first.fetch(:lower)],
        basename: 'reversed-rings'
      )
      # The POSIX handler maps this existing loader crash to exit 1. Windows
      # reports the native abnormal termination without a normal exit status.
      expect(reversed.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: Gem.win_platform? ? nil : 1,
        process_stdout: '',
        application_stdout: ''
      )
      expect(reversed.fetch(:host_stderr)).to include('Error: signal') unless Gem.win_platform?
      expect(reversed.fetch(:host_stderr)).not_to match(/sanitizer|warning|KERNEL_WARN/i)
      expect(reversed.fetch(:host_stderr)).not_to include('vm: initialize attributes', 'vm: add function <main>.')

      corrupt_lower = File.join(first.fetch(:directory), 'corrupt-stdlib.dabcb')
      corrupt_bytes = File.binread(first.fetch(:lower))
      corrupt_bytes[0, 3] = 'BAD'
      File.binwrite(corrupt_lower, corrupt_bytes)
      corrupt = run_vm(
        first.fetch(:directory),
        [corrupt_lower, first.fetch(:upper).fetch(:artifact)],
        basename: 'corrupt-lower'
      )
      expect(corrupt.slice(:status, :process_stdout, :application_stdout)).to eq(
        status: 1,
        process_stdout: '',
        application_stdout: ''
      )
      expected_corrupt_diagnostics = [
        'vm: predefine default classes',
        'VM options: autorun yes raw no cov no',
        'vm: invalid bytecode header: magic must be DAB.',
        'vm: VM destroyed!',
        'vm: reset $VM pointer',
      ]
      expect(corrupt.fetch(:host_stderr).lines(chomp: true)).to eq expected_corrupt_diagnostics
    end
  end
end

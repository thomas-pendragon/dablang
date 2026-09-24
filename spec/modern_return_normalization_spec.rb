require 'spec_helper'

require 'digest'
require 'open3'
require 'rbconfig'
require 'tmpdir'

require_relative '../src/compiler/_requires'
require_relative '../src/compiler/modern_bootstrap_parser'
previous_autorun = defined?($autorun) ? $autorun : nil
$autorun = false
require_relative '../src/frontend/frontend_modern_source'
$autorun = previous_autorun

describe 'Modern declared-return representation normalization' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:numeric_types) { %w[Fixnum Uint8 Uint16 Uint32 Uint64 Int8 Int16 Int32 Int64] }
  let(:private_code) { 0x0D }
  let(:vm) { ENV.fetch('DAB_MODERN_RETURN_VM', File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}")) }

  around do |example|
    Dir.mktmpdir('dab-modern-return') do |directory|
      @directory = directory
      example.run
    end
  end

  def lower_ring
    @lower_ring ||= begin
      path = File.join(@directory, 'stdlib.dabcb')
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(root, 'src/frontend/frontend_stdlib.rb'), "--output=#{path}", chdir: root
      )
      expect(status.exitstatus).to eq(0), stderr
      path
    end
  end

  def compile(source, legacy: false)
    path = File.join(@directory, legacy ? 'program.dab' : 'program.dabm')
    File.binwrite(path, source)
    context = InlineCompilerContext.new
    status = 0
    begin
      profile = legacy ? DabSyntaxProfile::LEGACY : DabSyntaxProfile::MODERN
      unit = DabSourceUnit.new(input: path, syntax_profile: profile)
      settings = {inputs: [path]}
      settings[:ring_base] = [lower_ring] unless legacy
      run_dab_compiler(settings, context, source_units: [unit])
    rescue InlineCompilerExit => e
      status = e.code
    end
    expect([status, context.stderr.string]).to eq([0, ''])
    context.stdout.string.b
  end

  def assemble(assembly, raw: false)
    options = raw ? ['--raw'] : []
    bytes, error, status = Open3.capture3(
      RbConfig.ruby, '-e', 'STDIN.binmode; STDOUT.binmode; load ARGV.shift',
      File.join(root, 'src/tobinary/tobinary.rb'), *options,
      stdin_data: assembly, binmode: true, chdir: root
    )
    expect(status.exitstatus).to eq(0), error
    bytes
  end

  def execute_assembly(assembly, raw: false, options: [])
    skip 'native VM is built by the complete gate' unless File.executable?(vm)

    artifact = File.join(@directory, 'program.dabcb')
    File.binwrite(artifact, assemble(assembly, raw: raw))
    flags = raw ? %w[--bare --raw] : []
    rings = !raw && @lower_ring ? [@lower_ring] : []
    stdout, stderr, status = Open3.capture3(vm, *flags, *options, *rings, artifact, binmode: true, chdir: root)
    [status.exitstatus, stdout, stderr]
  end

  def expected_integer(value, target)
    bits = target == 'Fixnum' ? 64 : target[/\d+/].to_i
    residue = value % (1 << bits)
    signed = !target.start_with?('Uint')
    signed && residue >= (1 << (bits - 1)) ? residue - (1 << bits) : residue
  end

  def load_integer(type, value, register = 'R0')
    opcode = type == 'Fixnum' ? 'NUMBER' : type.upcase
    "LOAD_#{opcode} #{register}, #{value}\n"
  end

  def public_class_probe(body)
    template = compile('func main(value) { print(value); print(value.class); }', legacy: true)
    class_symbol = template.match(%r{/\* class\s+\*/\s+INSTCALL R\d+, R\d+, (S\d+)})[1]
    instructions = yield(class_symbol, body)
    template.sub(/Fmain:\n.*?__Fmain_END:/m, "Fmain:\n#{instructions}RETURN RNIL\n__Fmain_END:")
  end

  it 'preserves Legacy, omitted metadata, bare/dead returns, and exact literals byte-for-byte' do
    controls = [
      ['func value<Int8>(actual<Int16>) { return actual; } func main() { print(value(255)); }', true,
       '18eeb2c7d5068023570bbe9ff9fc7ed557f198164cf471c4f5f865dc4ea7da1f',
       'ad479118e96c4ae05fddd6fa0865ab75f6c8b0828fd7db07170a2106c07f1195'],
      ["def value(actual:Int16)\nreturn actual\nend\ndef main()\nprint(value(255))\nend\n", false,
       '12b5796c9e00caabbde9e4d6c054d9706abf68e7d8690386d9eb8b17d5233ffa',
       '829d67a9a510be4d68d407a44ec4d20fbfa028601fd2dab01b668b1480a6bf51'],
      ["def main():String\nreturn\nreturn \"dead\"\nend\n", false,
       '16af6b72bec93fc012082585219f6282e092b0b9e3ba9edcac0e1a20e1bed299',
       '50688238b85444ce7d98e043bfac7984ee6dcdbcfd11a80c8539a87a361fb998'],
      ["def main():String\nreturn \"exact\"\nend\n", false,
       '89d6b1ae1fffe56d0c52239c0416b00a96bd89bb9cbfff6caf85b192bc90ca4f',
       'b7f6020e7a7e650400db37be26af750a55607019ad12c5f6201c5d45f6b10040'],
    ]
    controls.each do |source, legacy, assembly_hash, artifact_hash|
      assembly = compile(source, legacy: legacy)
      expect(Digest::SHA256.hexdigest(assembly)).to eq(assembly_hash)
      expect(Digest::SHA256.hexdigest(assemble(assembly))).to eq(artifact_hash)
    end
  end

  it 'keeps the private syscall out of both source-callable registries' do
    expect(KERNELCODES.fetch(private_code)).to eq('MODERN_RETURN_NORMALIZE')
    expect(SYSCALLS).not_to include('__modern_return_normalize')
    expect(BUILTINS).not_to include('__modern_return_normalize')
  end

  it 'normalizes a consumed parameter immediately before RETURN with a real value and Class register' do
    assembly = compile("def value(actual:Int16):Int8\nreturn actual\nend\n")
    expect(assembly).to match(/LOAD_CLASS (R\d+), 10.*?SYSCALL (R\d+), 13, (R\d+), \1\n\s+RETURN \2/m)
    expect(assembly).not_to include('CAST')
  end

  it 'admits all 81 numeric return pairs from parameter, local, literal, and direct-call provenance' do
    numeric_types.product(numeric_types).each do |actual, target|
      source = <<~DAB
        def producer():#{actual}
        return 255
        end
        def parameter(value:#{actual}):#{target}
        return value
        end
        def local():#{target}
        let value:#{actual} = 255
        return value
        end
        def direct():#{target}
        return producer()
        end
      DAB
      unit = DabSourceUnit.new(input: 'matrix.dabm', syntax_profile: DabSyntaxProfile::MODERN)
      expect do
        DabModernBootstrapParser.new(source.b, source_unit: unit).parse.lower_into(DabNodeUnit.new)
      end.not_to raise_error, "#{actual} -> #{target}"
    end
  end

  it 'preserves impossible mismatch diagnostics, including unreachable returns' do
    source = "def value():String\nreturn\nreturn 1\nend\n"
    unit = DabSourceUnit.new(input: 'mismatch.dabm', syntax_profile: DabSyntaxProfile::MODERN)
    expect do
      DabModernBootstrapParser.new(source.b, source_unit: unit).parse
    end.to raise_error(
      DabModernBootstrapParseError,
      'cannot return Modern value of type Fixnum from function "value" with declared return type String'
    )
  end

  it 'preserves exact nil and bare returns for every explicit declared type' do
    DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.each do |type|
      explicit = compile("def value():#{type}\nreturn nil\nend\n")
      bare = compile("def value():#{type}\nreturn\nend\n")
      expect(explicit).to eq(bare)
      expect(explicit).not_to match(/SYSCALL .*?, 13/)
      expect(explicit).to include('RETURN RNIL')
    end
  end

  it 'normalizes all 81 runtime integer pairs at zero, signed boundaries, and wrapping residues', :native do
    assembly = public_class_probe(nil) do |class_symbol, _|
      @expected_matrix = +''
      numeric_types.product(numeric_types).map do |actual, target|
        bits = actual == 'Fixnum' ? 64 : actual[/\d+/].to_i
        target_bits = target == 'Fixnum' ? 64 : target[/\d+/].to_i
        samples = [0, 1, 127, 128, 255, 256, 511, (1 << (bits - 1)) - 1,
                   1 << (bits - 1), (1 << bits) - 1, -1, -(1 << (bits - 1)),
                   (1 << (target_bits - 1)) - 1, 1 << (target_bits - 1),
                   (1 << target_bits) - 1, 1 << target_bits, (1 << target_bits) + 1]
        samples.map { |number| expected_integer(number, actual) }.uniq.map do |value|
          @expected_matrix << "#{expected_integer(value, target)}#{target}"
          load_integer(actual, value) + <<~ASM
            LOAD_CLASS R1, #{STANDARD_CLASSES_REV.fetch(target)}
            SYSCALL R0, #{private_code}, R0, R1
            SYSCALL RNIL, 0, R0
            INSTCALL R2, R0, #{class_symbol}
            SYSCALL RNIL, 0, R2
          ASM
        end.join
      end.join
    end
    status, stdout, stderr = execute_assembly(assembly)
    expect([status, stdout]).to eq([0, @expected_matrix]), stderr
  end

  it 'executes every numeric pair through literal, local, parameter, and direct-call returns', :native do
    definitions = []
    calls = []
    expected = +''
    numeric_types.product(numeric_types).each_with_index do |(actual, target), index|
      definitions << <<~DAB
        def producer#{index}():#{actual}
        return 255
        end
        def parameter#{index}(value:#{actual}):#{target}
        return value
        end
        def local#{index}():#{target}
        let value:#{actual} = 255
        return value
        end
        def direct#{index}():#{target}
        return producer#{index}()
        end
        def literal#{index}():#{target}
        return 255
        end
      DAB
      %w[parameter local direct literal].each do |kind|
        calls << "print(#{kind}#{index}(#{kind == 'parameter' ? "input#{actual}" : ''}))\nprint(\"|\")\n"
        value = kind == 'literal' ? 255 : expected_integer(255, actual)
        expected << "#{expected_integer(value, target)}|"
      end
    end
    inputs = numeric_types.map { |actual| "let input#{actual}:#{actual} = 255\n" }.join
    source = definitions.join + "def main()\n#{inputs}#{calls.join}end\n"
    status, stdout, stderr = execute_assembly(compile(source))
    expect(status).to eq(0), stderr
    expect(stdout).to eq(expected)
  end

  it 'passes actual nil through dynamic returns for every supported declared type', :native do
    before = execute_assembly("LOAD_NIL R0\n", raw: true, options: ['--output=reg[0]'])
    DabModernBootstrapParser::SUPPORTED_TYPE_NAMES.each do |type|
      assembly = "LOAD_NIL R0\nLOAD_CLASS R1, #{STANDARD_CLASSES_REV.fetch(type)}\nSYSCALL R0, 13, R0, R1\n"
      after = execute_assembly(assembly, raw: true, options: ['--output=reg[0]'])
      expect([after[0], after[1]]).to eq([0, before[1]]), type
    end
  end

  it 'passes exact String, Boolean, NilClass, IntPtr, and Float values without changing their representation', :native do
    instructions = {
      'String' => "LOAD_STRING R0, _TEXT, 4\n",
      'Boolean' => "LOAD_TRUE R0\n",
      'NilClass' => "LOAD_NIL R0\n",
      'IntPtr' => "LOAD_NIL R0\nCAST R0, R0, 15\n",
      'Float' => "LOAD_FLOAT R0, 1.25\n",
    }
    instructions.each do |type, load|
      raw = "JMP _CODE\n_TEXT:\nW_STRING \"text\"\n_CODE:\n#{load}"
      before = execute_assembly(raw, raw: true, options: ['--output=reg[0]'])
      normalized = raw + "LOAD_CLASS R1, #{STANDARD_CLASSES_REV.fetch(type)}\nSYSCALL R0, 13, R0, R1\n"
      after = execute_assembly(normalized, raw: true, options: ['--output=reg[0]'])
      expect([before[0], after[0]]).to eq([0, 0]), after[2]
      expect(after[1]).to eq(before[1]), type
    end
  end

  it 'keeps literal and composed String values and both Boolean values through declared returns', :native do
    source = <<~'DAB'
      def text(value:String):String
      return value
      end
      def composed(value:String):String
      return "#{value}!"
      end
      def flag(value:Boolean):Boolean
      return value
      end
      def main()
      print(text("text"))
      print(composed("text"))
      print(flag(true))
      print(flag(false))
      end
    DAB
    status, stdout, stderr = execute_assembly(compile(source))
    expect([status, stdout]).to eq([0, 'texttext!truefalse']), stderr
  end

  it 'preserves exact fixture output across forward, reverse, repeated compilation and two artifact builds' do
    names = %w[0083 0085 0086 0092 0094 0095 0112 0113 0114 0115]
    fixtures = names.map do |name|
      DabModernSourceFixture.load(Dir.glob(File.join(root, "test/modern_source/#{name}_*.dabmtest")).fetch(0))
    end
    [fixtures, fixtures.reverse, fixtures].each do |ordered|
      ordered.each do |fixture|
        expect(compile(fixture.source)).to eq(fixture.expected_stdout), fixture.path
      end
    end
    fixtures.each do |fixture|
      expect(assemble(fixture.expected_stdout)).to eq(assemble(fixture.expected_stdout)), fixture.path
    end
  end

  it 'executes fixture 0115 with the locked wrapped values and preserved nil', :native do
    fixture = DabModernSourceFixture.load(
      File.join(root, 'test/modern_source/0115_modern_return_representation.dabmtest')
    )
    status, stdout, stderr = execute_assembly(compile(fixture.source))
    expect([status, stdout]).to eq([0, fixture.expected_application_stdout]), stderr
  end

  it 'rejects nonnumeric mismatches using public type names and never accepts a Class as its instance', :native do
    cases = [
      ["LOAD_TRUE R0\n", 'String', 'Boolean'],
      ["LOAD_FLOAT R0, 1.5\n", 'Int8', 'Float'],
      ["LOAD_NUMBER R0, 1\n", 'NilClass', 'Fixnum'],
      ["LOAD_CLASS R0, 10\n", 'Int8', 'Class'],
      ["LOAD_NIL R0\nCAST R0, R0, 15\n", 'String', 'IntPtr'],
      ["JMP _CODE\n_TEXT:\nW_STRING \"text\"\n_CODE:\nLOAD_STRING R0, _TEXT, 4\n", 'Int8', 'String'],
    ]
    cases.each do |load, expected, actual|
      assembly = load + "LOAD_CLASS R1, #{STANDARD_CLASSES_REV.fetch(expected)}\nSYSCALL R2, 13, R0, R1\n"
      status, stdout, stderr = execute_assembly(assembly, raw: true)
      expect([status, stdout]).to eq([1, ''])
      expect(stderr.lines.grep(/vm: Modern return/)).to eq(["vm: Modern return expected #{expected}, got #{actual}.\n"])
    end
  end

  it 'validates each malformed private ABI branch in order before permitting actual nil', :native do
    prefix = "LOAD_NIL R0\nLOAD_CLASS R1, 10\n"
    cases = {
      'SYSCALL RNIL, 13' => 'expects 2 arguments, got 0',
      'SYSCALL R2, 13, R0' => 'expects 2 arguments, got 1',
      'SYSCALL R2, 13, R0, R1, R0' => 'expects 2 arguments, got 3',
      'SYSCALL RNIL, 13, RNIL, RNIL' => 'requires a result register',
      'SYSCALL R2, 13, RNIL, RNIL' => 'received an invalid value register',
      'SYSCALL R2, 13, R99, RNIL' => 'received an invalid value register',
      'SYSCALL R2, 13, R0, RNIL' => 'received an invalid target register',
      'SYSCALL R2, 13, R0, R99' => 'received an invalid target register',
      'SYSCALL R2, 13, R0, R0' => 'expects a supported declared result Class',
      "LOAD_CLASS R1, 0\nSYSCALL R2, 13, R0, R1" => 'expects a supported declared result Class',
      "LOAD_NIL R3\nSYSCALL R3, 13, R2, R1" => 'received an invalid value register',
      "LOAD_NIL R3\nSYSCALL R3, 13, R0, R2" => 'received an invalid target register',
    }
    cases.each do |instructions, message|
      status, stdout, stderr = execute_assembly("#{prefix}#{instructions}\n", raw: true)
      expect([status, stdout]).to eq([1, '']), instructions
      expect(stderr.lines.grep(/vm: internal Modern/)).to eq(
        ["vm: internal Modern return normalization #{message}.\n"]
      ), instructions
    end
  end

  it 'rejects an incompatible dynamic value before publishing a result or running later effects', :native do
    assembly = compile(<<~DAB)
      def value(actual:Int8):Int16
      print("before\\n")
      return actual
      print("dead\\n")
      end
      def main()
      print(value(1))
      print("after\\n")
      end
    DAB
    assembly = assembly.sub(/LOAD_ARG (R\d+), 0/, 'LOAD_TRUE \1')
    status, stdout, stderr = execute_assembly(assembly)
    expect([status, stdout]).to eq([1, "before\n"])
    expect(stderr.lines.grep(/vm: Modern return/)).to eq(["vm: Modern return expected Int16, got Boolean.\n"])
  end
end

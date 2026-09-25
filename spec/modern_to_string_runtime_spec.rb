require 'spec_helper'

require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tmpdir'
require_relative '../src/shared/opcodes'

describe 'Modern private to String runtime boundary' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:vm) { ENV.fetch('DAB_MODERN_TO_STRING_VM', File.join(root, "bin/cvm#{RbConfig::CONFIG.fetch('EXEEXT')}")) }
  let(:numeric_types) { %w[Fixnum Int8 Int16 Int32 Int64 Uint8 Uint16 Uint32 Uint64] }

  def run_raw(assembly, executable: vm, extra_arguments: [])
    skip 'native VM is built by the complete gate' unless File.executable?(executable)

    bytes, error, status = Open3.capture3(
      RbConfig.ruby, '-e', 'STDIN.binmode; STDOUT.binmode; load ARGV.shift',
      File.join(root, 'src/tobinary/tobinary.rb'), '--raw',
      stdin_data: assembly, binmode: true, chdir: root
    )
    expect(status.exitstatus).to eq(0), error
    Dir.mktmpdir('dab-to-string-runtime') do |directory|
      path = File.join(directory, 'program.dabcb')
      File.binwrite(path, bytes)
      stdout, stderr, result = Open3.capture3(executable, *extra_arguments, '--bare', '--raw', path,
                                              binmode: true, chdir: root)
      [result.exitstatus, stdout, stderr]
    end
  end

  def load_integer(type, value)
    "LOAD_#{type == 'Fixnum' ? 'NUMBER' : type.upcase} R0, #{value}\n"
  end

  it 'formats every signed and unsigned boundary as canonical untagged ASCII decimal' do
    numeric_types.each do |type|
      bits = type == 'Fixnum' ? 64 : type[/\d+/].to_i
      signed = !type.start_with?('Uint')
      values = signed ? [-(1 << (bits - 1)), -1, 0, 1, (1 << (bits - 1)) - 1] : [0, 1, (1 << bits) - 1]
      values.each do |value|
        status, stdout, error = run_raw("#{load_integer(type, value)}SYSCALL R1, 14, R0\nSYSCALL RNIL, 0, R1\n")
        expect([status, stdout]).to eq([0, value.to_s]), "#{type}(#{value}): #{error}"
      end
    end
  end

  it 'formats nil and both Booleans with the exact lowercase spelling' do
    {'NIL' => 'nil', 'TRUE' => 'true', 'FALSE' => 'false'}.each do |opcode, expected|
      status, stdout, error = run_raw("LOAD_#{opcode} R0\nSYSCALL R1, 14, R0\nSYSCALL RNIL, 0, R1\n")
      expect([status, stdout]).to eq([0, expected]), error
    end
  end

  it 'preserves the EX-038 normalization handoff including signed widening and nullable sentinels' do
    [
      ['Fixnum', 255, 'Int8', '-1'],
      ['Fixnum', 128, 'Int8', '-128'],
      ['Fixnum', 256, 'Uint8', '0'],
      ['Int16', 511, 'Int8', '-1'],
      ['Int8', -1, 'Uint16', '65535'],
      ['Uint8', 255, 'Int16', '255'],
    ].each do |source, value, target, expected|
      instructions = load_integer(source, value) + <<~ASM
        LOAD_CLASS R1, #{STANDARD_CLASSES_REV.fetch(target)}
        SYSCALL R2, 13, R0, R1
        SYSCALL R3, 14, R2
        SYSCALL RNIL, 0, R3
      ASM
      status, stdout, error = run_raw(instructions)
      expect([status, stdout]).to eq([0, expected]), error
    end
    status, stdout, error = run_raw("LOAD_NIL R0\nLOAD_CLASS R1, 10\nSYSCALL R2, 13, R0, R1\nSYSCALL R3, 14, R2\nSYSCALL RNIL, 0, R3\n")
    expect([status, stdout]).to eq([0, 'nil']), error
  end

  it 'validates count, real result, and initialized value registers in that order' do
    cases = {
      'SYSCALL RNIL, 14' => 'expects 1 argument, got 0',
      'SYSCALL RNIL, 14, RNIL, RNIL' => 'expects 1 argument, got 2',
      'SYSCALL RNIL, 14, RNIL' => 'requires a result register',
      'SYSCALL R2, 14, RNIL' => 'received an invalid value register',
      'SYSCALL R2, 14, R99' => 'received an invalid value register',
      "LOAD_NIL R3\nSYSCALL R2, 14, R1" => 'received an invalid value register',
    }
    cases.each do |instructions, message|
      status, stdout, error = run_raw("LOAD_NIL R0\n#{instructions}\n")
      expect([status, stdout]).to eq([1, '']), instructions
      expect(error.lines(chomp: true).grep(/vm: internal Modern/)).to eq(
        ["vm: internal Modern conversion to String #{message}."]
      )
    end
  end

  it 'rejects unsupported runtime tags without unboxing, publishing a value, or running later effects' do
    cases = [
      ["LOAD_FLOAT R0, 1.5\n", 'Float'],
      ["LOAD_NIL R0\nCAST R0, R0, 15\n", 'IntPtr'],
      ["LOAD_CLASS R0, 10\n", 'Class'],
      ["LOAD_TRUE R0\nBOX R0, R0\n", 'Box'],
      ["NEW_ARRAY R0\n", 'Array'],
    ]
    cases.each do |load, type|
      instructions = "LOAD_UINT8 R0, 7\nSYSCALL RNIL, 0, R0\n#{load}" \
                     "SYSCALL R1, 14, R0\nSYSCALL RNIL, 0, R1\nLOAD_TRUE R2\nSYSCALL RNIL, 0, R2\n"
      status, stdout, error = run_raw(instructions)
      expect([status, stdout]).to eq([1, '7'])
      expect(error.lines(chomp: true).grep(/vm: Modern/)).to eq(
        ["vm: Modern conversion to String does not support #{type}."]
      )
    end
  end

  it 'catches every converter allocation failure, retains ownership, and recovers without public dispatch', :native_harness do
    skip 'native VM is built by the complete gate' unless File.executable?(vm)

    library = File.join(root, 'bin', Gem.win_platform? ? 'pcre2.lib' : 'libpcre2.a')
    expect(File.file?(library)).to be(true), "Expected built PCRE2 dependency at #{library}"

    Dir.mktmpdir('dab-to-string-faults') do |directory|
      source = File.join(directory, 'faults.cpp')
      File.write(source, allocation_harness)
      syscall_source = File.join(root, 'src/cvm/syscalls.cpp')
      instrumented_source = File.join(directory, 'syscalls.cpp')
      runtime = File.read(syscall_source)
      allocation = '    std::unique_ptr<DabDynamicString> object(new DabDynamicString);'
      expect(runtime.scan(allocation).length).to eq(1)
      # Arm the test allocator at the real converter allocation in a temporary
      # translation unit, leaving production sources free of fault-injection hooks.
      File.write(instrumented_source, runtime.sub(allocation, <<~CPP.chomp))
            extern bool ex036_fail_conversion;
            extern long fail_after;
            if (ex036_fail_conversion) fail_after = 0;
        #{allocation}
      CPP
      compiler = Shellwords.split(ENV.fetch('CXX', RbConfig::CONFIG.fetch('CXX')))
      architecture = RUBY_PLATFORM.include?('darwin') ? %w[-arch x86_64] : []
      sources = Dir.glob(File.join(root, 'src/{cvm,cshared}/*.cpp')).reject do |path|
        path.end_with?('/main.cpp') || path == syscall_source
      end
      sanitizers = ENV.fetch('DAB_MODERN_TO_STRING_SANITIZERS', RUBY_PLATFORM.include?('linux') ? 'address,undefined' : '')
      [nil, *sanitizers.split(',')].each do |sanitizer|
        flags = sanitizer ? ["-fsanitize=#{sanitizer}", '-fno-omit-frame-pointer', '-fno-sanitize-recover=all'] : []
        binary = File.join(directory, "faults-#{sanitizer || 'normal'}#{RbConfig::CONFIG.fetch('EXEEXT')}")
        command = [
          *compiler, '-std=c++11', '-g', *architecture, *flags, '-iquote', root,
          '-iquote', File.join(root, 'src/cvm'),
          "-I#{File.join(root, 'build/dependencies/pcre2-10.47/src')}",
          '-DPCRE2_CODE_UNIT_WIDTH=8', '-DPCRE2_STATIC', %(-DDAB_VERSION="#{File.read(File.join(root, 'VERSION')).strip}"),
          source, instrumented_source, *sources, library, '-o', binary
        ]
        command << '-ldl' if RUBY_PLATFORM.include?('linux')
        output, error, status = Open3.capture3(*command, chdir: root)
        expect(status.exitstatus).to eq(0), "#{Shellwords.join(command)}\n#{output}\n#{error}"
        leaks = RUBY_PLATFORM.include?('linux') ? 1 : 0
        environment = {'ASAN_OPTIONS' => "detect_leaks=#{leaks}:halt_on_error=1", 'UBSAN_OPTIONS' => 'halt_on_error=1'}
        output, error, status = Open3.capture3(environment, binary, chdir: root)
        expect(status.exitstatus).to eq(0), "#{sanitizer}: #{output}\n#{error}"
        expect(output).to eq("allocation failures, identity, ABI, and recovery passed\n")
        expect(error).not_to match(/ERROR:|runtime error:|SUMMARY:.*Sanitizer/)
        instructions = "LOAD_UINT8 R0, 7\nSYSCALL RNIL, 0, R0\nSYSCALL R1, 14, R0\nSYSCALL RNIL, 0, R1\n"
        status, output, error = run_raw(instructions, executable: binary, extra_arguments: ['--fail-conversion'])
        expect([status, output]).to eq([1, '7'])
        expect(error.lines(chomp: true).grep(/vm: Modern/)).to eq(
          ['vm: Modern conversion to String failed: out of memory.']
        )
      end
    end
  end

  def allocation_harness
    <<~CPP
      #include <cstdlib>
      #include <new>
      #include <cassert>
      #include <clocale>
      #include <utility>
      long fail_after = -1;
      bool ex036_fail_conversion = false;
      static bool count_allocations = false;
      static long allocations = 0;
      void *operator new(std::size_t size)
      {
          if (fail_after == 0)
          {
              fail_after = -1;
              throw std::bad_alloc();
          }
          if (fail_after > 0) --fail_after;
          if (count_allocations) ++allocations;
          void *pointer = std::malloc(size ? size : 1);
          if (!pointer) throw std::bad_alloc();
          return pointer;
      }
      void operator delete(void *pointer) noexcept { std::free(pointer); }
      void *operator new[](std::size_t size) { return ::operator new(size); }
      void operator delete[](void *pointer) noexcept { std::free(pointer); }
      #define main dab_cli_main
      #include "src/cvm/main.cpp"
      #undef main
      #include "src/cshared/opcodes_syscalls.h"

      static void convert(DabVM &vm, uint16_t out = 1)
      {
          vm.kernelcall(dab_register_t(out), KERNEL_MODERN_TO_STRING, {dab_register_t(0)});
      }
      static void expect_error(DabVM &vm, dab_register_t out,
                               std::vector<dab_register_t> inputs, const char *message)
      {
          bool caught = false;
          try { vm.kernelcall(out, KERNEL_MODERN_TO_STRING, std::move(inputs)); }
          catch (const DabRuntimeError &error)
          {
              caught = true;
              assert(std::string(error.what()) == message);
          }
          assert(caught);
          assert(vm.register_get(dab_register_t(1)).data.type == TYPE_BOOLEAN);
      }
      int main(int argc, char **argv)
      {
          if (argc > 1 && std::string(argv[1]) == "--fail-conversion")
          {
              ex036_fail_conversion = true;
              return dab_cli_main(argc - 1, argv + 1);
          }
          DabVM vm;
          vm.define_default_classes();
          std::setlocale(LC_ALL, "");
          const auto r0 = dab_register_t(0);
          const auto r1 = dab_register_t(1);
          const auto nil = dab_register_t(65535);
          for (auto type : {CLASS_FIXNUM, CLASS_UINT64, CLASS_BOOLEAN, CLASS_NILCLASS, CLASS_STRING})
          {
              vm.get_class(type).add_reg_function("to_s", [](DabValue, std::vector<DabValue>) -> DabValue {
                  assert(false && "conversion must not dispatch public to_s");
                  return nullptr;
              });
          }
          vm.register_set(r0, DabValue(CLASS_UINT64, UINT64_MAX));
          vm.register_set(r1, DabValue(true));
          // Warm the register vector; only converter allocations are armed.
          std::vector<dab_register_t> operands{r0};
          count_allocations = true;
          vm.kernelcall(r1, KERNEL_MODERN_TO_STRING, std::move(operands));
          count_allocations = false;
          const auto allocation_total = allocations;
          assert(allocation_total >= 2);
          assert(vm.register_get(r1).data.type == TYPE_DYNAMICSTRING);
          assert(vm.register_get(r1).string() == "18446744073709551615");
          vm.register_set(r1, DabValue(true));
          const auto objects = DabMemoryCounter<COUNTER_OBJECT>::counter();
          const auto proxies = DabMemoryCounter<COUNTER_PROXY>::counter();
          for (long index = 0; index < allocation_total; ++index)
          {
              std::vector<dab_register_t> input{r0};
              fail_after = index;
              expect_error(vm, r1, std::move(input), "Modern conversion to String failed: out of memory");
              assert(fail_after == -1);
              assert(DabMemoryCounter<COUNTER_OBJECT>::counter() == objects);
              assert(DabMemoryCounter<COUNTER_PROXY>::counter() == proxies);
              convert(vm);
              assert(vm.register_get(r1).string() == "18446744073709551615");
              vm.register_set(r1, DabValue(true));
          }
          // The final allocation is publication into a new register. Failure
          // leaves the original vector and its existing result intact.
          operands = {r0};
          fail_after = allocation_total;
          expect_error(vm, dab_register_t(200), std::move(operands),
                       "Modern conversion to String failed: out of memory");
          assert(vm._registers.size() == 2);
          assert(DabMemoryCounter<COUNTER_OBJECT>::counter() == objects);
          assert(DabMemoryCounter<COUNTER_PROXY>::counter() == proxies);
          convert(vm);
          vm.register_set(r1, DabValue(true));

          for (auto type : {CLASS_LITERALSTRING, CLASS_DYNAMICSTRING})
          {
              auto input = DabValue(vm.get_class(type)).create_instance();
              if (type == CLASS_LITERALSTRING)
              {
                  auto *literal = static_cast<DabLiteralString *>(input.data.object->object);
                  literal->pointer = "literal";
                  literal->length = 7;
              }
              else
              {
                  static_cast<DabDynamicString *>(input.data.object->object)->value = "owned";
              }
              vm.register_set(r0, input);
              operands = {r0};
              fail_after = 0;
              vm.kernelcall(r1, KERNEL_MODERN_TO_STRING, std::move(operands));
              assert(fail_after == 0); // String identity allocates nothing.
              fail_after = -1;
              assert(vm.register_get(r1).data.object == input.data.object);
          }
          vm.register_set(r1, DabValue(true));
          expect_error(vm, nil, {}, "internal Modern conversion to String expects 1 argument, got 0");
          expect_error(vm, nil, {nil, nil}, "internal Modern conversion to String expects 1 argument, got 2");
          expect_error(vm, nil, {nil}, "internal Modern conversion to String requires a result register");
          expect_error(vm, r1, {nil}, "internal Modern conversion to String received an invalid value register");
          expect_error(vm, r1, {dab_register_t(99)}, "internal Modern conversion to String received an invalid value register");
          vm.register_set(dab_register_t(3), DabValue(nullptr));
          expect_error(vm, r1, {dab_register_t(2)}, "internal Modern conversion to String received an invalid value register");
          vm.register_set(r0, DabValue(CLASS_FLOAT, 1.5f));
          expect_error(vm, r1, {r0}, "Modern conversion to String does not support Float");
          vm.register_set(r0, DabValue(vm.get_class(CLASS_REGEX)).create_instance());
          expect_error(vm, r1, {r0}, "Modern conversion to String does not support Regex");
          vm.register_set(r0, DabValue(vm.get_class(CLASS_OBJECT)).create_instance());
          expect_error(vm, r1, {r0}, "Modern conversion to String does not support Object");
          std::vector<std::pair<DabValue, std::string>> boundaries{
              {DabValue(CLASS_INT8, int8_t(-128)), "-128"},
              {DabValue(CLASS_INT8, int8_t(127)), "127"},
              {DabValue(CLASS_INT16, int16_t(-32768)), "-32768"},
              {DabValue(CLASS_INT16, int16_t(32767)), "32767"},
              {DabValue(CLASS_INT32, INT32_MIN), "-2147483648"},
              {DabValue(CLASS_INT32, INT32_MAX), "2147483647"},
              {DabValue(CLASS_INT64, INT64_MIN), "-9223372036854775808"},
              {DabValue(CLASS_INT64, INT64_MAX), "9223372036854775807"},
              {DabValue(CLASS_UINT8, uint8_t(UINT8_MAX)), "255"},
              {DabValue(CLASS_UINT16, uint16_t(UINT16_MAX)), "65535"},
              {DabValue(CLASS_UINT32, UINT32_MAX), "4294967295"},
              {DabValue(CLASS_UINT64, UINT64_MAX), "18446744073709551615"},
              {DabValue(true), "true"},
              {DabValue(false), "false"},
              {DabValue(nullptr), "nil"},
          };
          DabValue fixnum;
          fixnum.data.type = TYPE_FIXNUM;
          fixnum.data.fixnum = INT64_MIN;
          boundaries.emplace_back(fixnum, "-9223372036854775808");
          fixnum.data.fixnum = INT64_MAX;
          boundaries.emplace_back(fixnum, "9223372036854775807");
          fixnum.data.fixnum = 0;
          boundaries.emplace_back(fixnum, "0");
          for (const auto &boundary : boundaries)
          {
              vm.register_set(r0, boundary.first);
              convert(vm);
              assert(vm.register_get(r1).data.type == TYPE_DYNAMICSTRING);
              assert(vm.register_get(r1).string() == boundary.second);
          }
          vm.register_set(r0, DabValue(nullptr));
          convert(vm);
          assert(vm.register_get(r1).string() == "nil");
          vm.register_set(r0, vm.register_get(r1));
          vm.register_set(r1, DabValue(nullptr));
          assert(vm.register_get(r0).string() == "nil"); // owned after result replacement
          std::puts("allocation failures, identity, ABI, and recovery passed");
      }
    CPP
  end
end

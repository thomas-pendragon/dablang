require 'fileutils'
require 'rbconfig'
require 'tmpdir'

require_relative '../../src/shared/opcodes'
require_relative 'legacy_source_vm_smoke'

module Dab
  module UnknownOpcodeContract
    EXPECTED_EXIT_STATUS = 2
    MALFORMED_VALUES = ->(highest) { [highest + 1, 0xff].uniq.freeze }
    SANITIZER_PATTERN = /AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|SUMMARY:/.freeze

    class ContractFailure < StandardError
    end

    class Commands
      def initialize(root:, binary_directory: 'bin')
        @root = root
        @binary_directory = binary_directory
      end

      def assembler
        [RbConfig.ruby, File.join(@root, 'src/tobinary/tobinary.rb')]
      end

      def native(tool, *arguments)
        executable = "#{tool}#{RbConfig::CONFIG.fetch('EXEEXT')}"
        [File.join(@root, @binary_directory, executable), *arguments]
      end
    end

    class Artifact
      HEADER_SIZE = 40
      SECTION_SIZE = 32
      FUNCTION_SIZE = 23
      FUNCTION_ARGUMENT_SIZE = 4

      attr_reader :bytes

      def initialize(bytes)
        @bytes = bytes.b
        parse_header
      end

      def code_position
        code.fetch(:position)
      end

      def boundary_position
        code_position + 1
      end

      def function_position(name)
        symbols = read_symbols
        position = functions.fetch(:position)
        limit = position + functions.fetch(:length)

        while position < limit
          fixed = bytes.byteslice(position, FUNCTION_SIZE)
          fail_contract('truncated function record') unless fixed&.bytesize == FUNCTION_SIZE

          symbol, _klass, address, argument_count, _length, _flags =
            fixed.unpack('S<S<Q<S<Q<C')
          return address if symbols.fetch(symbol) == name

          position += FUNCTION_SIZE + (FUNCTION_ARGUMENT_SIZE * (argument_count + 1))
        end

        fail_contract("function #{name.inspect} not found")
      end

      def mutate(position, opcode)
        code_limit = code.fetch(:position) + code.fetch(:length)
        unless position.between?(code.fetch(:position), code_limit - 1)
          fail_contract("mutation position #{position} is outside the code section")
        end

        mutated = bytes.dup
        mutated.setbyte(position, opcode)
        mutated
      end

    private

      def parse_header
        fixed = bytes.byteslice(0, HEADER_SIZE)
        fail_contract('truncated header') unless fixed&.bytesize == HEADER_SIZE

        magic, _version, _offset, header_size, data_size, section_count =
          fixed.unpack('a4L<Q<Q<Q<Q<')
        fail_contract('fixture is not DAB bytecode') unless magic == "DAB\0"
        unless bytes.bytesize == header_size + data_size
          fail_contract('fixture header and byte length disagree')
        end

        @sections = section_count.times.map do |index|
          offset = HEADER_SIZE + (index * SECTION_SIZE)
          section = bytes.byteslice(offset, SECTION_SIZE)
          fail_contract("truncated section record #{index}") unless section&.bytesize == SECTION_SIZE

          name, _zero1, _zero2, _special, position, length =
            section.unpack('a4L<L<L<Q<Q<')
          [name.delete_suffix("\0"), {position: position, length: length}]
        end.to_h
      end

      def code
        @sections.fetch('code')
      rescue KeyError
        fail_contract('fixture has no code section')
      end

      def functions
        @sections.fetch('fext')
      rescue KeyError
        fail_contract('fixture has no extended-function section')
      end

      def read_symbols
        symbol_data = @sections.fetch('symb')
        values = bytes.byteslice(symbol_data.fetch(:position), symbol_data.fetch(:length)).unpack('Q<*')
        values.map { |position| read_cstring(position) }
      rescue KeyError
        fail_contract('fixture has no symbol section')
      end

      def read_cstring(position)
        ending = bytes.index("\0", position)
        fail_contract("unterminated string at byte #{position}") unless ending

        bytes.byteslice(position, ending - position)
      end

      def fail_contract(message)
        raise ContractFailure.new(message)
      end
    end

    class Runner
      TIMEOUT = 10

      def initialize(root:, binary_directory: ENV.fetch('DAB_NATIVE_BINARY_DIRECTORY', 'bin'),
                     executor: LegacySourceVmSmoke::SystemExecutor.new,
                     output: $stdout, error: $stderr)
        @root = File.expand_path(root)
        @commands = Commands.new(root: @root, binary_directory: binary_directory)
        @executor = executor
        @output = output
        @error = error
      end

      def run
        Dir.mktmpdir('dab-unknown-opcode-contract') do |directory|
          control_path = assemble_control(directory)
          artifact = Artifact.new(File.binread(control_path))
          highest = REAL_OPCODES.keys.max
          fail_contract('the generated opcode set leaves no unknown byte value') if highest >= 0xff
          unless artifact.bytes.getbyte(artifact.boundary_position) == highest
            fail_contract("control boundary must contain highest valid opcode #{highest}")
          end

          validate_controls(control_path, highest)
          validate_malformed(directory, artifact, highest)
        end

        @output.puts('unknown opcode contract: PASSED')
        0
      rescue ContractFailure => e
        @error.puts("unknown opcode contract: FAILED: #{e.message}")
        1
      rescue SystemCallError, KeyError, TypeError => e
        @error.puts("unknown opcode contract: FAILED during setup: #{e.class}: #{e.message}")
        1
      end

    private

      def assemble_control(directory)
        source = File.binread(File.join(@root, 'test/unknown_opcode/control.dabca'))
        result = execute(@commands.assembler, input: source)
        require_success('assembler control', result)
        fail_contract('assembler produced empty control bytecode') if result.stdout.empty?

        path = File.join(directory, 'control.dabcb')
        File.binwrite(path, result.stdout)
        path
      end

      def validate_controls(path, highest)
        vm = require_success('cvm control', execute(@commands.native('cvm', path)))
        verbose = require_success(
          'cvm verbose control', execute(@commands.native('cvm', '--verbose', path))
        )
        disasm = require_success('cdisasm control', execute(@commands.native('cdisasm', path)))
        dumpcov = require_success('cdumpcov control', execute(@commands.native('cdumpcov', path)))

        fail_contract('cvm control wrote unexpected stdout') unless vm.stdout.empty?
        unless verbose.stdout == vm.stdout
          fail_contract('cvm verbose control changed program stdout')
        end
        opcode_name = REAL_OPCODES.fetch(highest).fetch(:name)
        unless disasm.stdout.lines.any? { |line| line.include?(opcode_name) }
          fail_contract("cdisasm did not decode highest valid opcode #{highest} (#{opcode_name})")
        end
        fail_contract('cdumpcov control output changed') unless dumpcov.stdout == "[]\n"
        [vm, verbose, disasm, dumpcov].each { |result| reject_sanitizer_report(result) }
      end

      def validate_malformed(directory, artifact, highest)
        execution_position = artifact.function_position('main')
        decode_position = artifact.boundary_position

        MALFORMED_VALUES.call(highest).each do |opcode|
          execute_path = write_mutation(directory, artifact, execution_position, opcode, 'execute')
          decode_path = write_mutation(directory, artifact, decode_position, opcode, 'decode')

          default = require_unknown(
            execute(@commands.native('cvm', execute_path)), 'cvm', 'execute', opcode,
            execution_position
          )
          verbose = require_unknown(
            execute(@commands.native('cvm', '--verbose', execute_path)), 'cvm', 'execute', opcode,
            execution_position
          )
          unless unknown_lines(default.stderr) == unknown_lines(verbose.stderr)
            fail_contract("cvm default and verbose rejection differ for opcode #{opcode}")
          end
          require_unknown(
            execute(@commands.native('cvm', '--debug', execute_path), input: "code\n"),
            'cvm', 'debug-disassembly', opcode, execution_position
          )
          require_unknown(
            execute(@commands.native('cdisasm', decode_path)), 'cdisasm', 'decode', opcode,
            decode_position
          )
          require_unknown(
            execute(@commands.native('cdumpcov', decode_path)), 'cdumpcov', 'decode', opcode,
            decode_position
          )
        end
      end

      def write_mutation(directory, artifact, position, opcode, stage)
        mutated = artifact.mutate(position, opcode)
        differences = artifact.bytes.bytes.zip(mutated.bytes).count { |before, after| before != after }
        fail_contract('malformed fixture must differ by exactly one byte') unless differences == 1

        path = File.join(directory, "#{stage}-#{opcode}.dabcb")
        File.binwrite(path, mutated)
        path
      end

      def require_unknown(result, consumer, stage, opcode, position)
        unless result.exit_code == EXPECTED_EXIT_STATUS && !result.timed_out
          fail_contract(
            "#{consumer} #{stage} opcode #{opcode} returned #{result.exit_code} " \
            "instead of #{EXPECTED_EXIT_STATUS}"
          )
        end
        validate_unknown_stdout(result.stdout, consumer, stage)
        expected = sprintf(
          "%s: %s: unknown opcode %d (0x%02x) at byte %d.\n",
          consumer, stage, opcode, opcode, position
        )
        unless unknown_lines(result.stderr) == [expected]
          fail_contract(
            "#{consumer} #{stage} opcode #{opcode} diagnostic mismatch: " \
            "#{unknown_lines(result.stderr).inspect}"
          )
        end
        reject_sanitizer_report(result)
        result
      end

      def unknown_lines(stderr)
        stderr.lines.grep(/unknown opcode/)
      end

      def validate_unknown_stdout(stdout, consumer, stage)
        return if stdout.empty?
        return if consumer == 'cdisasm' && stage == 'decode' && stdout.lines.length == 1 &&
                  stdout.match?(/NOP\s*\n\z/)

        fail_contract("#{consumer} #{stage} wrote unexpected stdout")
      end

      def reject_sanitizer_report(result)
        return unless result.stderr.match?(SANITIZER_PATTERN)

        fail_contract('native consumer emitted a sanitizer report')
      end

      def require_success(stage, result)
        return result if result.success?

        fail_contract("#{stage} returned #{result.exit_code}")
      end

      def execute(command, input: nil)
        @executor.call(command, input: input, chdir: @root, timeout: TIMEOUT)
      end

      def fail_contract(message)
        raise ContractFailure.new(message)
      end
    end
  end
end

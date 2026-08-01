require 'spec_helper'

require 'open3'
require 'tmpdir'

class V3StringTableArtifact
  FIXED_HEADER_SIZE = 40
  SECTION_SIZE = 32

  class << self
    def build(table_name: 'symb', string_data: "notcount\0", reference_offset: 3,
              reference: nil, table_data: nil, offset: 0, order: %w[data symb code])
      payloads = {
        'data' => string_data.b,
        table_name => table_data || ("\0" * 8).b,
        'code' => "\0".b,
      }
      header_size = FIXED_HEADER_SIZE + (SECTION_SIZE * order.length)
      positions = section_positions(order, payloads, header_size, offset)
      unless table_data
        pointer = reference || (positions.fetch('data') + reference_offset)
        payloads[table_name] = [pointer].pack('Q<')
      end

      [
        header(header_size, payloads.values_at(*order).sum(&:bytesize), order.length, offset),
        order.map { |name| section(name, positions.fetch(name), payloads.fetch(name).bytesize) },
        order.map { |name| payloads.fetch(name) },
      ].flatten.join
    end

    def rewrite_section(bytecode, index:, position: nil, length: nil)
      rewritten = bytecode.dup
      record = FIXED_HEADER_SIZE + (SECTION_SIZE * index)
      rewritten[record + 16, 8] = [position].pack('Q<') if position
      rewritten[record + 24, 8] = [length].pack('Q<') if length
      rewritten
    end

  private

    def header(header_size, data_size, section_count, offset)
      ["DAB\0".b, [3].pack('L'), [offset, header_size, data_size, section_count].pack('Q4')].join
    end

    def section(name, position, length)
      [name.b.ljust(4, "\0"), [0, 0, 0].pack('L3'), [position, length].pack('Q2')].join
    end

    def section_positions(order, payloads, header_size, offset)
      position = header_size + offset
      order.to_h do |name|
        current = position
        position += payloads.fetch(name).bytesize
        [name, current]
      end
    end
  end
end

describe 'Dab VM version 3 String and symbol data validation' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:vm) { ENV.fetch('DAB_CVM', File.join(root, 'bin/cvm')) }

  def run_vm(*bytecodes)
    Dir.mktmpdir('dab-bytecode-string-symbol-validation') do |directory|
      artifacts = bytecodes.each_with_index.map do |bytecode, index|
        artifact = File.join(directory, "input-#{index}.dabcb")
        File.binwrite(artifact, bytecode)
        artifact
      end
      return Open3.capture3(vm, '--raw', *artifacts, chdir: directory)
    end
  end

  def expect_rejection(bytecode, diagnostic)
    stdout, stderr, status = run_vm(bytecode)

    expect(status.exitstatus).to eq(1), stderr
    expect(stdout).to eq('')
    expect(stderr).to include("vm: invalid bytecode String/symbol data: #{diagnostic}.\n")
    expect(stderr).not_to match(/Assertion|AddressSanitizer|runtime error:|Segmentation fault/)
  end

  it 'preserves valid symbol references into the middle of NUL-terminated data' do
    stdout, stderr, status = run_vm(V3StringTableArtifact.build)

    expect(status).to be_success, stderr
    expect(stdout).to eq('')
    expect(stderr).not_to include('invalid bytecode String/symbol data')
  end

  it 'preserves valid symbol data in a later artifact with a nonzero base offset' do
    first = V3StringTableArtifact.build
    second = V3StringTableArtifact.build(offset: first.bytesize)

    stdout, stderr, status = run_vm(first, second)

    expect(status).to be_success, stderr
    expect(stdout).to eq('')
    expect(stderr).not_to include('invalid bytecode String/symbol data')
  end

  it 'validates every input before loading String or symbol data from an earlier input' do
    valid = V3StringTableArtifact.build
    invalid = V3StringTableArtifact.build(table_data: "\0" * 7)

    stdout, stderr, status = run_vm(valid, invalid)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq('')
    expect(stderr).to include(
      "vm: invalid bytecode String/symbol data: symb section length is not a multiple of 8.\n"
    )
    expect(stderr).not_to include('vm: newformat:')
  end

  {
    'a truncated symbol reference record' => [
      V3StringTableArtifact.build(table_data: "\0" * 7),
      'symb section length is not a multiple of 8',
    ],
    'a symbol table range below the artifact offset' => [
      V3StringTableArtifact.rewrite_section(
        V3StringTableArtifact.build(offset: 1000),
        index: 1,
        position: 999
      ),
      'symb section starts before the artifact',
    ],
    'an overflowing symbol table range' => [
      V3StringTableArtifact.rewrite_section(
        V3StringTableArtifact.build,
        index: 1,
        length: (2**64) - 8
      ),
      'symb section range is outside the artifact',
    ],
    'a symbol reference below a nonzero artifact offset' => [
      V3StringTableArtifact.build(offset: 1000, reference: 999),
      'symb entry 0 reference starts before the artifact',
    ],
    'a symbol reference outside the artifact' => [
      V3StringTableArtifact.build(reference: (2**64) - 1),
      'symb entry 0 reference is outside the artifact',
    ],
    'a symbol without a terminating NUL byte' => [
      V3StringTableArtifact.build(
        string_data: 'unterminated',
        reference_offset: 0,
        order: %w[symb code data]
      ),
      'symb entry 0 String is not NUL-terminated within the artifact',
    ],
    'a truncated coverage String reference record' => [
      V3StringTableArtifact.build(table_name: 'cove', table_data: "\0" * 7,
                                  order: %w[data cove code]),
      'cove section length is not a multiple of 8',
    ],
    'an invalid coverage String reference' => [
      V3StringTableArtifact.build(table_name: 'cove', reference: (2**64) - 1,
                                  order: %w[data cove code]),
      'cove entry 0 reference is outside the artifact',
    ],
    'a coverage String without a terminating NUL byte' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        string_data: 'unterminated',
        reference_offset: 0,
        order: %w[cove code data]
      ),
      'cove entry 0 String is not NUL-terminated within the artifact',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} deterministically" do
      expect_rejection(bytecode, diagnostic)
    end
  end
end

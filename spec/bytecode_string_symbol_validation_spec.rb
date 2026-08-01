require 'spec_helper'

require 'open3'
require 'tmpdir'

class V3StringTableArtifact
  FIXED_HEADER_SIZE = 40
  SECTION_SIZE = 32

  class << self
    def build(table_name: 'symb', string_data: "notcount\0", reference_offset: 3,
              reference: nil, table_data: nil, offset: 0, order: %w[data symb code],
              code_data: nil, load_string: nil)
      payloads = {
        'data' => string_data.b,
        table_name => table_data || ("\0" * 8).b,
        'code' => code_data || (load_string ? ("\0" * 20).b : "\0".b),
      }
      header_size = FIXED_HEADER_SIZE + (SECTION_SIZE * order.length)
      positions = section_positions(order, payloads, header_size, offset)
      unless table_data
        pointer = reference || (positions.fetch('data') + reference_offset)
        payloads[table_name] = [pointer].pack('Q<')
      end
      if load_string
        pointer = load_string.fetch(:reference, positions.fetch('data') +
          load_string.fetch(:reference_offset, 0))
        length = load_string.fetch(:length)
        payloads['code'] = [0x12, 0xffff, pointer, length].pack('CSQQ') + [0].pack('C')
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
  let(:cdisasm) { ENV.fetch('DAB_CDISASM', File.join(root, 'bin/cdisasm')) }
  let(:cdumpcov) { ENV.fetch('DAB_CDUMPCOV', File.join(root, 'bin/cdumpcov')) }

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
    expected = if diagnostic.start_with?('invalid bytecode header:')
                 "vm: #{diagnostic}"
               else
                 "vm: invalid bytecode String/symbol data: #{diagnostic}"
               end
    expect(stderr).to include(expected)
    expect(stderr).not_to match(/Assertion|AddressSanitizer|runtime error:|Segmentation fault/)
  end

  def run_consumer(executable, bytecode, *arguments)
    Dir.mktmpdir('dab-bytecode-string-symbol-consumer') do |directory|
      artifact = File.join(directory, 'input.dabcb')
      File.binwrite(artifact, bytecode)
      return Open3.capture3(executable, *arguments, artifact, chdir: directory)
    end
  end

  def expect_consumer_rejection(executable, bytecode, consumer, diagnostic, *arguments)
    stdout, stderr, status = run_consumer(executable, bytecode, *arguments)

    expect(status.exitstatus).to eq(1), "#{stdout}\n#{stderr}"
    expect(stdout).to eq('')
    expect(stderr).to include("#{consumer}: invalid bytecode String/symbol data: #{diagnostic}")
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

  it 'preserves a later Ring symbol reference into an earlier loaded artifact' do
    first = V3StringTableArtifact.build
    first_string = V3StringTableArtifact::FIXED_HEADER_SIZE + (V3StringTableArtifact::SECTION_SIZE * 3) + 3
    second = V3StringTableArtifact.build(offset: first.bytesize, reference: first_string)

    stdout, stderr, status = run_vm(first, second)

    expect(status).to be_success, stderr
    expect(stdout).to eq('')
    expect(stderr).not_to include('invalid bytecode String/symbol data')
  end

  it 'preserves a valid LOAD_STRING byte range without inventing a NUL terminator' do
    bytecode = V3StringTableArtifact.build(
      string_data: 'payload',
      order: %w[data code],
      load_string: {length: 7}
    )

    stdout, stderr, status = run_vm(bytecode)

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
      'invalid bytecode header: section 1 position precedes header offset',
    ],
    'an overflowing symbol table range' => [
      V3StringTableArtifact.rewrite_section(
        V3StringTableArtifact.build,
        index: 1,
        length: (2**64) - 8
      ),
      'invalid bytecode header: section 1 range overflows uint64',
    ],
    'a symbol reference below a nonzero artifact offset' => [
      V3StringTableArtifact.build(offset: 1000, reference: 999),
      'symb entry 0 reference is outside the artifact',
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

  it 'rejects a truncated LOAD_STRING record before native disassembly' do
    bytecode = V3StringTableArtifact.build(
      order: %w[data code],
      code_data: [0x12, 0].pack('CC')
    )

    expect_consumer_rejection(cdisasm, bytecode, 'cdisasm', 'code instruction')
  end

  {
    'an outside LOAD_STRING reference' => [
      V3StringTableArtifact.build(
        order: %w[data code],
        load_string: {reference: (2**64) - 1, length: 1}
      ),
      'LOAD_STRING',
    ],
    'an overflowing LOAD_STRING length' => [
      V3StringTableArtifact.build(
        order: %w[data code],
        load_string: {length: (2**64) - 1}
      ),
      'LOAD_STRING',
    ],
    'a truncated LOAD_STRING instruction record' => [
      V3StringTableArtifact.build(order: %w[data code], code_data: [0x12, 0].pack('CC')),
      'code instruction',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} before VM execution" do
      expect_rejection(bytecode, diagnostic)
    end
  end

  it 'preserves valid W_STRING and W_SYMBOL output' do
    stdout, stderr, status = run_consumer(cdisasm, V3StringTableArtifact.build, '--with-headers')

    expect(status).to be_success, stderr
    expect(stdout).to include('W_STRING "notcount"')
    expect(stdout).to include('W_SYMBOL ')
  end

  it 'preserves unterminated unreferenced data as W_BYTE output' do
    bytecode = V3StringTableArtifact.build(
      string_data: 'raw',
      order: %w[data code]
    )

    stdout, stderr, status = run_consumer(cdisasm, bytecode, '--with-headers')

    expect(status).to be_success, stderr
    expect(stdout).not_to include('W_STRING')
    expect(stdout.scan('W_BYTE').length).to eq(3)
  end

  {
    'a partial W_SYMBOL record' => [
      V3StringTableArtifact.build(table_data: "\0" * 7),
      'symb section length is not a multiple of 8',
    ],
    'a W_SYMBOL reference to an unterminated String' => [
      V3StringTableArtifact.build(
        string_data: 'unterminated',
        reference_offset: 0,
        order: %w[symb code data]
      ),
      'symb entry 0 String is not NUL-terminated within the artifact',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} before native disassembly" do
      expect_consumer_rejection(cdisasm, bytecode, 'cdisasm', diagnostic, '--with-headers')
    end
  end

  it 'preserves a valid coverage pointer and C String' do
    bytecode = V3StringTableArtifact.build(
      table_name: 'cove',
      order: %w[data cove code]
    )

    stdout, stderr, status = run_consumer(cdumpcov, bytecode)

    expect(status).to be_success, stderr
    expect(stdout).to eq("[{\"file\": \"count\", \"lines\": []}]\n")
  end

  it 'preserves a valid coverage pointer in a nonzero-offset artifact' do
    bytecode = V3StringTableArtifact.build(
      table_name: 'cove',
      offset: 1000,
      order: %w[data cove code]
    )

    stdout, stderr, status = run_consumer(cdumpcov, bytecode)

    expect(status).to be_success, stderr
    expect(stdout).to eq("[{\"file\": \"count\", \"lines\": []}]\n")
  end

  {
    'a partial coverage pointer record' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        table_data: "\0" * 7,
        order: %w[data cove code]
      ),
      'cove section length is not a multiple of 8',
    ],
    'an outside coverage pointer' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        reference: (2**64) - 1,
        order: %w[data cove code]
      ),
      'cove entry 0 reference is outside the artifact',
    ],
    'a coverage pointer below a nonzero artifact offset' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        offset: 1000,
        reference: 999,
        order: %w[data cove code]
      ),
      'cove entry 0 reference is outside the artifact',
    ],
    'an unterminated coverage C String' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        string_data: 'unterminated',
        reference_offset: 0,
        order: %w[cove code data]
      ),
      'cove entry 0 String is not NUL-terminated within the artifact',
    ],
    'a truncated opcode record' => [
      V3StringTableArtifact.build(
        table_name: 'cove',
        order: %w[data cove code],
        code_data: [0x22, 0].pack('CC')
      ),
      'code instruction',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} before coverage decoding" do
      expect_consumer_rejection(cdumpcov, bytecode, 'cdumpcov', diagnostic)
    end
  end
end

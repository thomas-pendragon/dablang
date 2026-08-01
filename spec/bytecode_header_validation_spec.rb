require 'spec_helper'

require 'open3'
require 'tmpdir'

class BytecodeHeaderValidationSpecSupport
  FIXED_HEADER_SIZE = 40
  SECTION_SIZE = 32

  class << self
    def header(magic: "DAB\0", version: 3, offset: 0, size_of_header: FIXED_HEADER_SIZE,
               size_of_data: 0, section_count: 0)
      [
        magic.b,
        [version].pack('L'),
        [offset, size_of_header, size_of_data, section_count].pack('Q4'),
      ].join
    end

    def section(name: 'code', zero1: 0, zero2: 0, special_index: 0, position: 72, length: 1)
      [
        name.b.ljust(4, "\0").byteslice(0, 4),
        [zero1, zero2, special_index].pack('L3'),
        [position, length].pack('Q2'),
      ].join
    end
  end
end

describe 'Dab VM bytecode header validation' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:vm) { ENV.fetch('DAB_CVM', File.join(root, 'bin/cvm')) }

  def header(**arguments)
    BytecodeHeaderValidationSpecSupport.header(**arguments)
  end

  def section(**arguments)
    BytecodeHeaderValidationSpecSupport.section(**arguments)
  end

  def run_vm(*bytecodes)
    Dir.mktmpdir('dab-bytecode-header-validation') do |directory|
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
    expect(stderr).to include("vm: invalid bytecode header: #{diagnostic}.\n")
    expect(stderr).not_to match(/Assertion|AddressSanitizer|runtime error:|Segmentation fault/)
  end

  it 'loads and executes a valid version 3 control artifact unchanged' do
    bytecode = [
      header(
        size_of_header: BytecodeHeaderValidationSpecSupport::FIXED_HEADER_SIZE +
          BytecodeHeaderValidationSpecSupport::SECTION_SIZE,
        size_of_data: 1,
        section_count: 1
      ),
      section,
      "\x00",
    ].join

    stdout, stderr, status = run_vm(bytecode)

    expect(status).to be_success, stderr
    expect(stdout).to eq('')
    expect(stderr).not_to include('invalid bytecode header')
  end

  it 'validates every input before processing or mutating state for an earlier input' do
    valid = [
      header(
        size_of_header: BytecodeHeaderValidationSpecSupport::FIXED_HEADER_SIZE +
          BytecodeHeaderValidationSpecSupport::SECTION_SIZE,
        size_of_data: 1,
        section_count: 1
      ),
      section,
      "\x00",
    ].join
    invalid = header.byteslice(0, 39)

    stdout, stderr, status = run_vm(valid, invalid)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq('')
    expect(stderr).to include(
      "vm: invalid bytecode header: fixed header is truncated (expected 40 bytes).\n"
    )
    expect(stderr).not_to include('vm: newformat:')
  end

  {
    'an empty input' => ['', 'fixed header is truncated (expected 40 bytes)'],
    'the last byte of the fixed header missing' => [
      BytecodeHeaderValidationSpecSupport.header.byteslice(0, 39),
      'fixed header is truncated (expected 40 bytes)',
    ],
    'a truncated section record' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 72, section_count: 1) +
        BytecodeHeaderValidationSpecSupport.section.byteslice(0, 31),
      'declared section table exceeds input',
    ],
    'a complete record missing from a multi-section table' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 104, section_count: 2) +
        BytecodeHeaderValidationSpecSupport.section,
      'declared section table exceeds input',
    ],
    'a wrong magic' => [
      BytecodeHeaderValidationSpecSupport.header(magic: "BAD\0"),
      'magic must be DAB',
    ],
    'a nonzero header marker' => [
      BytecodeHeaderValidationSpecSupport.header(magic: 'DABX'),
      'header zero marker must be 0',
    ],
    'an unsupported version' => [
      BytecodeHeaderValidationSpecSupport.header(version: 2),
      'unsupported bytecode version (expected 3)',
    ],
    'a header size smaller than its declared table' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 71, section_count: 1) +
        BytecodeHeaderValidationSpecSupport.section,
      'size_of_header does not match section_count',
    ],
    'a header size larger than its declared table' => [
      [
        BytecodeHeaderValidationSpecSupport.header(size_of_header: 73, section_count: 1),
        BytecodeHeaderValidationSpecSupport.section,
        "\0",
      ].join,
      'size_of_header does not match section_count',
    ],
    'an overflowing section count' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 40, section_count: (2**64) - 1),
      'section table size overflows uint64',
    ],
    'a nonzero first section reserved field' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 72, section_count: 1) +
        BytecodeHeaderValidationSpecSupport.section(zero1: 1),
      'section 0 reserved fields must be zero',
    ],
    'a nonzero second section reserved field' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 72, section_count: 1) +
        BytecodeHeaderValidationSpecSupport.section(zero2: 1),
      'section 0 reserved fields must be zero',
    ],
    'a nonzero section special index' => [
      BytecodeHeaderValidationSpecSupport.header(size_of_header: 72, section_count: 1) +
        BytecodeHeaderValidationSpecSupport.section(special_index: 1),
      'section 0 reserved fields must be zero',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} deterministically" do
      expect_rejection(bytecode, diagnostic)
    end
  end
end

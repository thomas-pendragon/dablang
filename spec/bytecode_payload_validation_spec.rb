require 'spec_helper'

require 'open3'
require 'tmpdir'

class BytecodePayloadValidationSpecSupport
  FIXED_HEADER_SIZE = 40
  SECTION_SIZE = 32
  MAX_UINT64 = (2**64) - 1

  class << self
    def header(offset: 0, size_of_header: FIXED_HEADER_SIZE, size_of_data: 0, section_count: 0)
      [
        "DAB\0".b,
        [3].pack('L'),
        [offset, size_of_header, size_of_data, section_count].pack('Q4'),
      ].join
    end

    def section(position:, length:, name: 'code')
      [
        name.b.ljust(4, "\0").byteslice(0, 4),
        [0, 0, 0].pack('L3'),
        [position, length].pack('Q2'),
      ].join
    end

    def artifact(sections:, payload:, offset: 0, size_of_data: payload.bytesize)
      size_of_header = FIXED_HEADER_SIZE + (sections.length * SECTION_SIZE)
      [
        header(
          offset: offset,
          size_of_header: size_of_header,
          size_of_data: size_of_data,
          section_count: sections.length
        ),
        *sections.map { |attributes| section(**attributes) },
        payload,
      ].join
    end
  end
end

describe 'Dab VM bytecode section payload validation' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:vm) { ENV.fetch('DAB_CVM', File.join(root, 'bin/cvm')) }

  def header(**arguments)
    BytecodePayloadValidationSpecSupport.header(**arguments)
  end

  def artifact(**arguments)
    BytecodePayloadValidationSpecSupport.artifact(**arguments)
  end

  def run_vm(*bytecodes)
    Dir.mktmpdir('dab-bytecode-payload-validation') do |directory|
      artifacts = bytecodes.each_with_index.map do |bytecode, index|
        path = File.join(directory, "input-#{index}.dabcb")
        File.binwrite(path, bytecode)
        path
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
    expect(stderr).not_to include('vm: newformat:')
  end

  it 'preserves valid offsets, gaps, out-of-order ranges, adjacency, and a zero-length end section' do
    first = artifact(
      sections: [{name: 'code', position: 72, length: 1}],
      payload: "\0"
    )
    second = artifact(
      offset: first.bytesize,
      sections: [
        {name: 'data', position: 211, length: 1},
        {name: 'code', position: 210, length: 1},
        {name: 'meta', position: 212, length: 0},
      ],
      payload: "\0\0\0"
    )

    stdout, stderr, status = run_vm(first, second)

    expect(status).to be_success, stderr
    expect(stdout).to eq('')
    expect(stderr).not_to include('invalid bytecode header')
  end

  it 'validates every payload before appending or mutating state for an earlier input' do
    valid = artifact(
      sections: [{name: 'code', position: 72, length: 1}],
      payload: "\0"
    )
    invalid = artifact(
      sections: [{name: 'code', position: 72, length: 2}],
      payload: "\0"
    )

    stdout, stderr, status = run_vm(valid, invalid)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq('')
    expect(stderr).to include(
      "vm: invalid bytecode header: section 0 range exceeds declared payload.\n"
    )
    expect(stderr).not_to include('vm: newformat:')
  end

  support = BytecodePayloadValidationSpecSupport

  {
    'a declared bytecode size that overflows uint64' => [
      support.header(size_of_data: BytecodePayloadValidationSpecSupport::MAX_UINT64),
      'declared bytecode size overflows uint64',
    ],
    'a declared payload shorter than the input' => [
      [support.header, "\0"].join,
      'size_of_header and size_of_data do not match input size',
    ],
    'a declared payload longer than the input' => [
      support.header(size_of_data: 1),
      'size_of_header and size_of_data do not match input size',
    ],
    'an offset that overflows the absolute payload start' => [
      support.artifact(
        offset: BytecodePayloadValidationSpecSupport::MAX_UINT64 - 71,
        sections: [{name: 'code', position: 0, length: 1}],
        payload: "\0"
      ),
      'section payload start overflows uint64',
    ],
    'an offset that overflows the absolute payload end' => [
      support.artifact(
        offset: BytecodePayloadValidationSpecSupport::MAX_UINT64 - 72,
        sections: [{name: 'code', position: 0, length: 1}],
        payload: "\0"
      ),
      'section payload end overflows uint64',
    ],
    'a section position before header.offset' => [
      support.artifact(
        offset: 100,
        sections: [{name: 'code', position: 99, length: 1}],
        payload: "\0"
      ),
      'section 0 position precedes header offset',
    ],
    'a section starting inside the header' => [
      support.artifact(
        offset: 100,
        sections: [{name: 'code', position: 171, length: 1}],
        payload: "\0"
      ),
      'section 0 starts before declared payload',
    ],
    'a section starting after the payload' => [
      support.artifact(
        sections: [{name: 'code', position: 74, length: 0}],
        payload: "\0"
      ),
      'section 0 starts after declared payload',
    ],
    'a section range that overflows uint64' => [
      support.artifact(
        sections: [
          {
            name: 'code',
            position: 72,
            length: BytecodePayloadValidationSpecSupport::MAX_UINT64,
          },
        ],
        payload: "\0"
      ),
      'section 0 range overflows uint64',
    ],
    'a section range extending beyond the payload' => [
      support.artifact(
        sections: [{name: 'code', position: 72, length: 2}],
        payload: "\0"
      ),
      'section 0 range exceeds declared payload',
    ],
    'overlapping non-empty section ranges' => [
      support.artifact(
        sections: [
          {name: 'code', position: 104, length: 2},
          {name: 'data', position: 105, length: 1},
        ],
        payload: "\0\0"
      ),
      'section 0 overlaps section 1',
    ],
  }.each do |description, (bytecode, diagnostic)|
    it "rejects #{description} deterministically" do
      expect_rejection(bytecode, diagnostic)
    end
  end
end

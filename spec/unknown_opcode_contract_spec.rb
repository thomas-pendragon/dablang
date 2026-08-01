require 'spec_helper'

require 'stringio'

require_relative '../lib/dab/unknown_opcode_contract'

describe Dab::UnknownOpcodeContract::Runner do
  let(:root) { File.expand_path('..', __dir__) }

  it 'rejects unknown opcodes across every native instruction decoder' do
    output = StringIO.new
    error = StringIO.new
    status = described_class.new(root: root, output: output, error: error).run

    expect(status).to eq(0), error.string
    expect(output.string).to eq("unknown opcode contract: PASSED\n")
    expect(error.string).to eq('')
  end
end

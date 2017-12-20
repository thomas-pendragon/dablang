require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

def parse_bin(bin)
  bin.split(/\s+/).map do |char|
    [char.to_i(16)].pack('C')
  end.join
end

describe DabBinReader, readbin: true do
  it 'parses header' do
    header = parse_bin('44 41 42 00 02 00 00 00  c0 00 00 00 00 00 00 00
                        bd 04 00 00 00 00 00 00  05 00 00 00 00 00 00 00')

    result = DabBinReader.new.parse_header(header)

    expected = {
      dab: 'DAB',
      zero: 0,
      version: 2,
      size_of_header: 192,
      size_of_data: 1213,
      sections_count: 5,
    }

    expect(result).to eq(expected)
  end
end

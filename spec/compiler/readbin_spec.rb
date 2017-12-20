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

  it 'parses section' do
    section = parse_bin('63 6f 64 65 00 00 00 00  00 00 00 00 00 00 00 00
                         c2 00 00 00 00 00 00 00  2c 03 00 00 00 00 00 00')

    result = DabBinReader.new.parse_section(section)

    expected = {
      name: 'code',
      zero1: 0,
      zero2: 0,
      zero3: 0,
      address: 194,
      length: 812,
    }

    expect(result).to eq(expected)
  end

  it 'parses whole header' do
    header = parse_bin('44 41 42 00 02 00 00 00  c0 00 00 00 00 00 00 00
                        bd 04 00 00 00 00 00 00  05 00 00 00 00 00 00 00
                        64 61 74 61 00 00 00 00  00 00 00 00 00 00 00 00
                        c0 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00
                        63 6f 64 65 00 00 00 00  00 00 00 00 00 00 00 00
                        c2 00 00 00 00 00 00 00  2c 03 00 00 00 00 00 00
                        73 79 6d 64 00 00 00 00  00 00 00 00 00 00 00 00
                        ee 03 00 00 00 00 00 00  53 00 00 00 00 00 00 00
                        73 79 6d 62 00 00 00 00  00 00 00 00 00 00 00 00
                        41 04 00 00 00 00 00 00  88 00 00 00 00 00 00 00
                        66 75 6e 63 00 00 00 00  00 00 00 00 00 00 00 00
                        c9 04 00 00 00 00 00 00  b4 00 00 00 00 00 00 00')

    result = DabBinReader.new.parse_whole_header(header)

    expected = {
      dab: 'DAB',
      zero: 0,
      version: 2,
      size_of_header: 192,
      size_of_data: 1213,
      sections_count: 5,
      sections: [
        {name: 'data', zero1: 0, zero2: 0, zero3: 0, address: 192, length: 2},
        {name: 'code', zero1: 0, zero2: 0, zero3: 0, address: 194, length: 812},
        {name: 'symd', zero1: 0, zero2: 0, zero3: 0, address: 1006, length: 83},
        {name: 'symb', zero1: 0, zero2: 0, zero3: 0, address: 1089, length: 136},
        {name: 'func', zero1: 0, zero2: 0, zero3: 0, address: 1225, length: 180},
      ],
    }

    expect(result).to eq(expected)
  end
end

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

  it 'parses symbols' do
    symd = parse_bin('21 00 21 3d 00 2b 00 2d  00 3d 3d 00 5b 5d 00 63
                      6f 75 6e 74 00 65 61 63  68 00 65 61 63 68 5f 77
                      69 74 68 5f 69 6e 64 65  78 00 66 69 72 73 74 00
                      69 73 00 6c 61 73 74 00  6c 65 6e 67 74 68 00 6d
                      61 69 6e 00 70 75 74 73  00 74 6f 5f 62 6f 6f 6c
                      00 7c 00                                        ')

    symb = parse_bin('ee 03 00 00 00 00 00 00  f0 03 00 00 00 00 00 00
                      f3 03 00 00 00 00 00 00  f5 03 00 00 00 00 00 00
                      f7 03 00 00 00 00 00 00  fa 03 00 00 00 00 00 00
                      fd 03 00 00 00 00 00 00  03 04 00 00 00 00 00 00
                      08 04 00 00 00 00 00 00  18 04 00 00 00 00 00 00
                      1e 04 00 00 00 00 00 00  21 04 00 00 00 00 00 00
                      26 04 00 00 00 00 00 00  2d 04 00 00 00 00 00 00
                      32 04 00 00 00 00 00 00  37 04 00 00 00 00 00 00
                      3f 04 00 00 00 00 00 00                          ')

    result = DabBinReader.new.parse_symbols(symd, 1006, symb)

    expected = ['!', '!=', '+', '-', '==', '[]', 'count', 'each', 'each_with_index',
                'first', 'is', 'last', 'length', 'main', 'puts', 'to_bool', '|']

    expect(result).to eq(expected)
  end
end

require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

def parse_bin(bin)
  bin.split(/\s+/).map do |char|
    [char.to_i(16)].pack('C')
  end.join
end

describe DabBinReader, readbin: true do
  it 'parses header' do
    header = parse_bin('44 41 42 00 03 00 00 00
                        ff 00 00 00 00 00 00 00
                        c0 00 00 00 00 00 00 00
                        bd 04 00 00 00 00 00 00  05 00 00 00 00 00 00 00')

    result = DabBinReader.new.parse_header(header)

    expected = {
      dab: 'DAB',
      zero: 0,
      offset: 255,
      version: 3,
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
    header = parse_bin('44 41 42 00 03 00 00 00
                        00 00 00 00 00 00 00 00
                        c0 00 00 00 00 00 00 00
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
      version: 3,
      offset: 0,
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

  it 'parses functions' do
    symbols = ['!', '!=', '+', '-', '==', '[]', 'count', 'each', 'each_with_index',
               'first', 'is', 'last', 'length', 'main', 'puts', 'to_bool']

    func = parse_bin('0d 00 ff ff d0 00 00 00  00 00 00 00 0e 00 ff ff
                      02 01 00 00 00 00 00 00  04 00 05 00 2e 01 00 00
                      00 00 00 00 07 00 05 00  03 02 00 00 00 00 00 00
                      08 00 05 00 5e 02 00 00  00 00 00 00 09 00 05 00
                      bb 02 00 00 00 00 00 00  0b 00 05 00 d9 02 00 00
                      00 00 00 00 0f 00 05 00  3d 03 00 00 00 00 00 00
                      0f 00 03 00 63 03 00 00  00 00 00 00 0f 00 02 00
                      6c 03 00 00 00 00 00 00  0f 00 04 00 8a 03 00 00
                      00 00 00 00 00 00 00 00  93 03 00 00 00 00 00 00
                      01 00 00 00 b1 03 00 00  00 00 00 00 0f 00 00 00
                      d1 03 00 00 00 00 00 00  0f 00 01 00 da 03 00 00
                      00 00 00 00                                     ')

    result = DabBinReader.new.parse_functions(func, symbols)

    expected = [
      {symbol: 'main', klass: 65535, address: 208},
      {symbol: 'puts', klass: 65535, address: 258},
      {symbol: '==', klass: 5, address: 302},
      {symbol: 'each', klass: 5, address: 515},
      {symbol: 'each_with_index', klass: 5, address: 606},
      {symbol: 'first', klass: 5, address: 699},
      {symbol: 'last', klass: 5, address: 729},
      {symbol: 'to_bool', klass: 5, address: 829},
      {symbol: 'to_bool', klass: 3, address: 867},
      {symbol: 'to_bool', klass: 2, address: 876},
      {symbol: 'to_bool', klass: 4, address: 906},
      {symbol: '!', klass: 0, address: 915},
      {symbol: '!=', klass: 0, address: 945},
      {symbol: 'to_bool', klass: 0, address: 977},
      {symbol: 'to_bool', klass: 1, address: 986},
    ]

    expect(result).to eq(expected)
  end
end

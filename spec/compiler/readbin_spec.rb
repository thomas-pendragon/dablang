require 'spec_helper'

require_relative '../../src/compiler/_requires'

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

    result = DabBinReader.new.parse_symbols(symd, 1006, symb, 0)

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
      {symbol: 'main', klass: nil, address: 208},
      {symbol: 'puts', klass: nil, address: 258},
      {symbol: '==', klass: 'Array', address: 302},
      {symbol: 'each', klass: 'Array', address: 515},
      {symbol: 'each_with_index', klass: 'Array', address: 606},
      {symbol: 'first', klass: 'Array', address: 699},
      {symbol: 'last', klass: 'Array', address: 729},
      {symbol: 'to_bool', klass: 'Array', address: 829},
      {symbol: 'to_bool', klass: 'Boolean', address: 867},
      {symbol: 'to_bool', klass: 'Fixnum', address: 876},
      {symbol: 'to_bool', klass: 'NilClass', address: 906},
      {symbol: '!', klass: 'Object', address: 915},
      {symbol: '!=', klass: 'Object', address: 945},
      {symbol: 'to_bool', klass: 'Object', address: 977},
      {symbol: 'to_bool', klass: 'String', address: 986},
    ]

    expect(result).to eq(expected)
  end

  it 'parses klasses' do
    symbols = ['!', '!=', '%', '&', '*', '+', '-', '/', '<', '==', '>', '>>', 'SDL_CreateRenderer',
               'SDL_CreateWindow', 'SDL_Delay', 'SDL_GetPerformanceCounter', 'SDL_GetPerformanceFrequency',
               'SDL_Init', 'SDL_PollEvent', 'SDL_RenderClear', 'SDL_RenderDrawLine', 'SDL_RenderPresent',
               'SDL_SetRenderDrawColor', 'SnakeGame', 'SnakePoint', 'SnakeRandom']

    clas = parse_bin('00 01 00 00 18 00 01 01  00 00 19 00 02 01 00 00
                      17 00                                           ')

    result = DabBinReader.new.parse_klasses(clas, symbols)

    expected = [
      {index: 256, parent_index: 0, symbol: 'SnakePoint'},
      {index: 257, parent_index: 0, symbol: 'SnakeRandom'},
      {index: 258, parent_index: 0, symbol: 'SnakeGame'},
    ]

    expect(result).to eq(expected)
  end

  it 'parses extended functions' do
    symbols = ['!', '!=', '+', '-', '==', '[]', 'a', 'b', 'count', 'each', 'each_with_index', 'first',
               'foo', 'is', 'last', 'length', 'main', 'other', 'puts', 'string', 'to_bool']

    fext = parse_bin('0c 00 ff ff cb 00 00 00  00 00 00 00 02 00 06 00
                      01 00 07 00 06 00 ff ff  00 00 10 00 ff ff db 00
                      00 00 00 00 00 00 00 00  ff ff 00 00 12 00 ff ff
                      f1 00 00 00 00 00 00 00  01 00 13 00 00 00 ff ff
                      00 00 04 00 05 00 1d 01  00 00 00 00 00 00 01 00
                      11 00 00 00 ff ff 00 00  09 00 05 00 f2 01 00 00
                      00 00 00 00 00 00 ff ff  00 00 0a 00 05 00 4d 02
                      00 00 00 00 00 00 00 00  ff ff 00 00 0b 00 05 00
                      aa 02 00 00 00 00 00 00  00 00 ff ff 00 00 0e 00
                      05 00 c8 02 00 00 00 00  00 00 00 00 ff ff 00 00
                      14 00 05 00 2c 03 00 00  00 00 00 00 00 00 ff ff
                      00 00 14 00 03 00 52 03  00 00 00 00 00 00 00 00
                      ff ff 00 00 14 00 02 00  5b 03 00 00 00 00 00 00
                      00 00 ff ff 00 00 14 00  04 00 79 03 00 00 00 00
                      00 00 00 00 ff ff 00 00  00 00 00 00 82 03 00 00
                      00 00 00 00 00 00 ff ff  00 00 01 00 00 00 a0 03
                      00 00 00 00 00 00 01 00  11 00 00 00 ff ff 00 00
                      14 00 00 00 c0 03 00 00  00 00 00 00 00 00 ff ff
                      00 00 14 00 01 00 c9 03  00 00 00 00 00 00 00 00
                      ff ff 00 00                                     ')

    result = DabBinReader.new.parse_extended_functions(fext, symbols)

    expected = [
      {
        symbol: 'foo',
        klass: nil,
        address: 203,
        args: [
          {symbol: 'a', klass: 'String'},
          {symbol: 'b', klass: 'Uint8'},
        ],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'main',
        klass: nil,
        address: 219,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'puts',
        klass: nil,
        address: 241,
        args: [
          {symbol: 'string', klass: 'Object'},
        ],
        ret: {klass: 'Object'},
      },
      {
        symbol: '==',
        klass: 'Array',
        address: 285,
        args: [
          {symbol: 'other', klass: 'Object'},
        ],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'each',
        klass: 'Array',
        address: 498,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'each_with_index',
        klass: 'Array',
        address: 589,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'first',
        klass: 'Array',
        address: 682,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'last',
        klass: 'Array',
        address: 712,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'Array',
        address: 812,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'Boolean',
        address: 850,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'Fixnum',
        address: 859,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'NilClass',
        address: 889,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: '!',
        klass: 'Object',
        address: 898,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: '!=',
        klass: 'Object',
        address: 928,
        args: [
          {symbol: 'other', klass: 'Object'},
        ],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'Object',
        address: 960,
        args: [],
        ret: {klass: 'Object'},
      },
      {
        symbol: 'to_bool',
        klass: 'String',
        address: 969,
        args: [],
        ret: {klass: 'Object'},
      },
    ]

    expect(result).to eq(expected)
  end

  it 'parses whole binary image' do
    binary = parse_bin('44 41 42 00 03 00 00 00  00 00 00 00 00 00 00 00  c8 00 00 00 00 00 00 00  b2 04 00 00 00 00 00 00
				    	05 00 00 00 00 00 00 00  64 61 74 61 00 00 00 00  00 00 00 00 00 00 00 00  c8 00 00 00 00 00 00 00
				    	0e 00 00 00 00 00 00 00  63 6f 64 65 00 00 00 00  00 00 00 00 00 00 00 00  d6 00 00 00 00 00 00 00
				    	1f 03 00 00 00 00 00 00  73 79 6d 64 00 00 00 00  00 00 00 00 00 00 00 00  f5 03 00 00 00 00 00 00
				    	51 00 00 00 00 00 00 00  73 79 6d 62 00 00 00 00  00 00 00 00 00 00 00 00  46 04 00 00 00 00 00 00
				    	80 00 00 00 00 00 00 00  66 75 6e 63 00 00 00 00  00 00 00 00 00 00 00 00  c6 04 00 00 00 00 00 00
				    	b4 00 00 00 00 00 00 00  0a 00 68 65 6c 6c 6f 20  77 6f 72 6c 64 00 00 26  00 00 11 00 00 ca 00 00
				    	00 00 00 00 00 0b 00 00  00 00 00 00 00 1e ff ff  00 01 00 00 20 ff ff 26  00 00 17 00 00 00 00 1e
				    	ff ff 00 01 00 00 11 01  00 c8 00 00 00 00 00 00  00 01 00 00 00 00 00 00  00 1e ff ff 00 01 01 00
				    	20 ff ff 26 00 00 17 00  00 00 00 0d 01 00 05 00  1c 02 00 00 00 0a 00 01  01 00 1c 03 00 02 00 00
				    	00 00 19 03 00 07 00 10  00 04 04 00 20 04 00 18  03 00 13 05 00 1c 06 00  05 00 06 00 00 1c 07 00
				    	00 00 06 00 00 1c 08 00  06 00 01 00 01 07 00 19  08 00 07 00 10 00 04 09  00 20 09 00 18 03 00 10
				    	0a 00 00 00 00 00 00 00  00 00 13 0b 00 1c 0c 00  0b 00 06 00 00 18 03 00  1c 0d 00 0a 00 01 00 01
				    	0c 00 19 0d 00 07 00 50  00 13 0e 00 1c 0f 00 0e  00 05 00 01 0a 00 1c 10  00 00 00 05 00 01 0a 00
				    	1c 11 00 0f 00 01 00 01  10 00 19 11 00 07 00 10  00 04 12 00 20 12 00 18  03 00 10 13 00 01 00 00
				    	00 00 00 00 00 1c 0a 00  0a 00 02 00 01 13 00 18  a9 ff 03 14 00 20 14 00  26 00 00 10 00 00 00 00
				    	00 00 00 00 00 00 13 01  00 1c 02 00 01 00 06 00  00 18 03 00 1c 03 00 00  00 01 00 01 02 00 19 03
				    	00 07 00 32 00 13 04 00  1c 05 00 04 00 05 00 01  00 00 1f ff ff 01 05 00  10 06 00 01 00 00 00 00
				    	00 00 00 1c 00 00 00 00  02 00 01 06 00 18 c7 ff  20 ff ff 26 00 00 10 00  00 00 00 00 00 00 00 00
				    	00 13 01 00 1c 02 00 01  00 06 00 00 18 03 00 1c  03 00 00 00 01 00 01 02  00 19 03 00 07 00 34 00
				    	13 04 00 1c 05 00 04 00  05 00 01 00 00 1f ff ff  02 05 00 00 00 10 06 00  01 00 00 00 00 00 00 00
				    	1c 00 00 00 00 02 00 01  06 00 18 c5 ff 20 ff ff  26 00 00 10 00 00 00 00  00 00 00 00 00 00 13 01
				    	00 1c 02 00 01 00 05 00  01 00 00 20 02 00 26 00  00 13 00 00 1c 01 00 00  00 06 00 00 10 02 00 00
				    	00 00 00 00 00 00 00 1c  03 00 01 00 04 00 01 02  00 19 03 00 07 00 0d 00  20 ff ff 18 36 00 13 04
				    	00 1c 05 00 04 00 06 00  00 10 06 00 01 00 00 00  00 00 00 00 1c 07 00 05  00 03 00 01 06 00 13 08
				    	00 1c 09 00 08 00 05 00  01 07 00 20 09 00 18 03  00 00 26 00 00 13 00 00  1c 01 00 00 00 06 00 00
				    	10 02 00 00 00 00 00 00  00 00 00 1c 03 00 01 00  01 00 01 02 00 20 03 00  26 00 00 13 00 00 20 00
				    	00 26 00 00 13 00 00 10  01 00 00 00 00 00 00 00  00 00 1c 02 00 00 00 01  00 01 01 00 20 02 00 26
				    	00 00 04 00 00 20 00 00  26 00 00 13 00 00 1c 01  00 00 00 0f 00 00 04 02  00 1c 03 00 01 00 04 00
				    	01 02 00 20 03 00 26 00  00 17 00 00 00 00 13 01  00 1c 02 00 01 00 04 00  01 00 00 1c 03 00 02 00
				    	00 00 00 20 03 00 26 00  00 03 00 00 20 00 00 26  00 00 13 00 00 1c 01 00  00 00 0c 00 00 10 02 00
				    	00 00 00 00 00 00 00 00  1c 03 00 01 00 01 00 01  02 00 20 03 00 21 00 21  3d 00 2b 00 2d 00 3d 3d
				    	00 5b 5d 00 63 6f 75 6e  74 00 65 61 63 68 00 65  61 63 68 5f 77 69 74 68  5f 69 6e 64 65 78 00 66
				    	69 72 73 74 00 69 73 00  6c 61 73 74 00 6c 65 6e  67 74 68 00 6d 61 69 6e  00 70 75 74 73 00 74 6f
				    	5f 62 6f 6f 6c 00 f5 03  00 00 00 00 00 00 f7 03  00 00 00 00 00 00 fa 03  00 00 00 00 00 00 fc 03
				    	00 00 00 00 00 00 fe 03  00 00 00 00 00 00 01 04  00 00 00 00 00 00 04 04  00 00 00 00 00 00 0a 04
				    	00 00 00 00 00 00 0f 04  00 00 00 00 00 00 1f 04  00 00 00 00 00 00 25 04  00 00 00 00 00 00 28 04
				    	00 00 00 00 00 00 2d 04  00 00 00 00 00 00 34 04  00 00 00 00 00 00 39 04  00 00 00 00 00 00 3e 04
				    	00 00 00 00 00 00 0d 00  ff ff d7 00 00 00 00 00  00 00 0e 00 ff ff f7 00  00 00 00 00 00 00 04 00
				    	05 00 23 01 00 00 00 00  00 00 07 00 05 00 f8 01  00 00 00 00 00 00 08 00  05 00 53 02 00 00 00 00
				    	00 00 09 00 05 00 b0 02  00 00 00 00 00 00 0b 00  05 00 ce 02 00 00 00 00  00 00 0f 00 05 00 32 03
				    	00 00 00 00 00 00 0f 00  03 00 58 03 00 00 00 00  00 00 0f 00 02 00 61 03  00 00 00 00 00 00 0f 00
				    	04 00 7f 03 00 00 00 00  00 00 00 00 00 00 88 03  00 00 00 00 00 00 01 00  00 00 a6 03 00 00 00 00
				    	00 00 0f 00 00 00 c6 03  00 00 00 00 00 00 0f 00  01 00 cf 03 00 00 00 00  00 00                  ')

    result = DabBinReader.new.parse_dab_binary(binary)

    expected = {
      header: {
        dab: 'DAB',
        zero: 0,
        version: 3,
        offset: 0,
        size_of_header: 200,
        size_of_data: 1202,
        sections_count: 5,
        sections: [
          {name: 'data', zero1: 0, zero2: 0, zero3: 0, address: 200, length: 14},
          {name: 'code', zero1: 0, zero2: 0, zero3: 0, address: 214, length: 799},
          {name: 'symd', zero1: 0, zero2: 0, zero3: 0, address: 1013, length: 81},
          {name: 'symb', zero1: 0, zero2: 0, zero3: 0, address: 1094, length: 128},
          {name: 'func', zero1: 0, zero2: 0, zero3: 0, address: 1222, length: 180},
        ],
      },
      symbols: [
        '!', '!=', '+', '-', '==', '[]', 'count', 'each', 'each_with_index', 'first',
        'is', 'last', 'length', 'main', 'puts', 'to_bool'
      ],
      all_symbols: [
        '!', '!=', '+', '-', '==', '[]', 'count', 'each', 'each_with_index', 'first',
        'is', 'last', 'length', 'main', 'puts', 'to_bool'
      ],
      functions: [
        {symbol: 'main', klass: nil, address: 215},
        {symbol: 'puts', klass: nil, address: 247},
        {symbol: '==', klass: 'Array', address: 291},
        {symbol: 'each', klass: 'Array', address: 504},
        {symbol: 'each_with_index', klass: 'Array', address: 595},
        {symbol: 'first', klass: 'Array', address: 688},
        {symbol: 'last', klass: 'Array', address: 718},
        {symbol: 'to_bool', klass: 'Array', address: 818},
        {symbol: 'to_bool', klass: 'Boolean', address: 856},
        {symbol: 'to_bool', klass: 'Fixnum', address: 865},
        {symbol: 'to_bool', klass: 'NilClass', address: 895},
        {symbol: '!', klass: 'Object', address: 904},
        {symbol: '!=', klass: 'Object', address: 934},
        {symbol: 'to_bool', klass: 'Object', address: 966},
        {symbol: 'to_bool', klass: 'String', address: 975},
      ],
    }

    expect(result).to eq(expected)
  end

  it 'should parse whole header with offsets' do
    header = parse_bin('44 41 42 00 03 00 00 00  04 03 00 00 00 00 00 00
                        c8 00 00 00 00 00 00 00  79 02 00 00 00 00 00 00
                        05 00 00 00 00 00 00 00  64 61 74 61 00 00 00 00
                        00 00 00 00 00 00 00 00  cc 03 00 00 00 00 00 00
                        0e 00 00 00 00 00 00 00  63 6f 64 65 00 00 00 00
                        00 00 00 00 00 00 00 00  da 03 00 00 00 00 00 00
                        41 00 00 00 00 00 00 00  73 79 6d 64 00 00 00 00
                        00 00 00 00 00 00 00 00  1b 04 00 00 00 00 00 00
                        d2 00 00 00 00 00 00 00  73 79 6d 62 00 00 00 00
                        00 00 00 00 00 00 00 00  ed 04 00 00 00 00 00 00
                        40 01 00 00 00 00 00 00  66 75 6e 63 00 00 00 00
                        00 00 00 00 00 00 00 00  2d 06 00 00 00 00 00 00
                        18 00 00 00 00 00 00 00 ')

    result = DabBinReader.new.parse_whole_header_with_offset(header)

    expected = {
      dab: 'DAB',
      zero: 0,
      version: 3,
      offset: 772,
      size_of_header: 200,
      size_of_data: 633,
      sections_count: 5,
      sections: [
        {name: 'data', zero1: 0, zero2: 0, zero3: 0, address: 972 - 772, length: 14},
        {name: 'code', zero1: 0, zero2: 0, zero3: 0, address: 986 - 772, length: 65},
        {name: 'symd', zero1: 0, zero2: 0, zero3: 0, address: 1051 - 772, length: 210},
        {name: 'symb', zero1: 0, zero2: 0, zero3: 0, address: 1261 - 772, length: 320},
        {name: 'func', zero1: 0, zero2: 0, zero3: 0, address: 1581 - 772, length: 24},
      ],
    }

    expect(result).to eq(expected)
  end

  it 'should parse whole images for ring > 0' do
    binary = parse_bin('44 41 42 00 03 00 00 00 04 03 00 00 00 00 00 00 c8 00 00 00 00 00 00 00 79 02 00 00 00 00 00 00
                        05 00 00 00 00 00 00 00 64 61 74 61 00 00 00 00 00 00 00 00 00 00 00 00 cc 03 00 00 00 00 00 00
                        0e 00 00 00 00 00 00 00 63 6f 64 65 00 00 00 00 00 00 00 00 00 00 00 00 da 03 00 00 00 00 00 00
                        41 00 00 00 00 00 00 00 73 79 6d 64 00 00 00 00 00 00 00 00 00 00 00 00 1b 04 00 00 00 00 00 00
                        d2 00 00 00 00 00 00 00 73 79 6d 62 00 00 00 00 00 00 00 00 00 00 00 00 ed 04 00 00 00 00 00 00
                        40 01 00 00 00 00 00 00 66 75 6e 63 00 00 00 00 00 00 00 00 00 00 00 00 2d 06 00 00 00 00 00 00
                        18 00 00 00 00 00 00 00 20 77 6f 72 6c 64 00 6c 65 76 65 6c 31 00 00 26 00 00 11 00 00 cc 03 00
                        00 00 00 00 00 06 00 00 00 00 00 00 00 1e ff ff 00 01 00 00 20 ff ff 26 00 00 11 00 00 d3 03 00
                        00 00 00 00 00 06 00 00 00 00 00 00 00 1e ff ff 00 01 00 00 20 ff ff 66 6f 6f 00 6c 65 76 65 6c
                        30 00 6e 65 77 00 63 6c 61 73 73 00 74 6f 5f 73 00 5f 5f 63 6f 6e 73 74 72 75 63 74 00 5f 5f 64
                        65 73 74 72 75 63 74 00 69 73 00 3d 3d 00 75 70 63 61 73 65 00 6c 65 6e 67 74 68 00 5b 5d 00 2b
                        00 21 3d 00 3e 00 3e 3d 00 3c 3d 00 3c 00 2d 00 2a 00 2f 00 25 00 3c 3c 00 3e 3e 00 7c 00 26 00
                        62 79 74 65 73 77 61 70 00 66 65 74 63 68 5f 69 6e 74 33 32 00 63 6f 75 6e 74 00 73 68 69 66 74
                        00 69 6e 73 65 72 74 00 5b 5d 3d 00 6a 6f 69 6e 00 5f 5f 69 6d 70 6f 72 74 5f 6c 69 62 63 00 5f
                        5f 69 6d 70 6f 72 74 5f 73 64 6c 00 5f 5f 69 6d 70 6f 72 74 5f 70 71 00 7c 7c 00 26 26 00 62 61
                        72 00 6c 65 76 65 6c 31 00 1b 04 00 00 00 00 00 00 1f 04 00 00 00 00 00 00 26 04 00 00 00 00 00
                        00 2a 04 00 00 00 00 00 00 30 04 00 00 00 00 00 00 35 04 00 00 00 00 00 00 41 04 00 00 00 00 00
                        00 4c 04 00 00 00 00 00 00 4f 04 00 00 00 00 00 00 52 04 00 00 00 00 00 00 59 04 00 00 00 00 00
                        00 60 04 00 00 00 00 00 00 63 04 00 00 00 00 00 00 65 04 00 00 00 00 00 00 68 04 00 00 00 00 00
                        00 6a 04 00 00 00 00 00 00 6d 04 00 00 00 00 00 00 70 04 00 00 00 00 00 00 72 04 00 00 00 00 00
                        00 74 04 00 00 00 00 00 00 76 04 00 00 00 00 00 00 78 04 00 00 00 00 00 00 7a 04 00 00 00 00 00
                        00 7d 04 00 00 00 00 00 00 80 04 00 00 00 00 00 00 82 04 00 00 00 00 00 00 84 04 00 00 00 00 00
                        00 8d 04 00 00 00 00 00 00 99 04 00 00 00 00 00 00 9f 04 00 00 00 00 00 00 a5 04 00 00 00 00 00
                        00 ac 04 00 00 00 00 00 00 b0 04 00 00 00 00 00 00 b5 04 00 00 00 00 00 00 c3 04 00 00 00 00 00
                        00 d0 04 00 00 00 00 00 00 dc 04 00 00 00 00 00 00 df 04 00 00 00 00 00 00 e2 04 00 00 00 00 00
                        00 e6 04 00 00 00 00 00 00 26 00 ff ff db 03 00 00 00 00 00 00 27 00 ff ff fb 03 00 00 00 00 00
                        00')

    result = DabBinReader.new.parse_dab_binary(binary)

    expected = {
      header: {
        dab: 'DAB',
        zero: 0,
        version: 3,
        offset: 772,
        size_of_header: 200,
        size_of_data: 633,
        sections_count: 5,
        sections: [
          {name: 'data', zero1: 0, zero2: 0, zero3: 0, address: 972 - 772, length: 14},
          {name: 'code', zero1: 0, zero2: 0, zero3: 0, address: 986 - 772, length: 65},
          {name: 'symd', zero1: 0, zero2: 0, zero3: 0, address: 1051 - 772, length: 210},
          {name: 'symb', zero1: 0, zero2: 0, zero3: 0, address: 1261 - 772, length: 320},
          {name: 'func', zero1: 0, zero2: 0, zero3: 0, address: 1581 - 772, length: 24},
        ],
      },
      symbols: [
        'foo', 'level0', 'new', 'class', 'to_s', '__construct', '__destruct', 'is', '==', 'upcase', 'length', '[]', '+',
        '!=', '>', '>=', '<=', '<', '-', '*', '/', '%', '<<', '>>', '|', '&', 'byteswap', 'fetch_int32', 'count', 'shift',
        'insert', '[]=', 'join', '__import_libc', '__import_sdl', '__import_pq', '||', '&&', 'bar', 'level1'
      ],
      all_symbols: [
        'foo', 'level0', 'new', 'class', 'to_s', '__construct', '__destruct', 'is', '==', 'upcase', 'length', '[]', '+',
        '!=', '>', '>=', '<=', '<', '-', '*', '/', '%', '<<', '>>', '|', '&', 'byteswap', 'fetch_int32', 'count', 'shift',
        'insert', '[]=', 'join', '__import_libc', '__import_sdl', '__import_pq', '||', '&&', 'bar', 'level1'
      ],
      functions: [
        {symbol: 'bar', klass: nil, address: 987},
        {symbol: 'level1', klass: nil, address: 1019},
      ],
    }

    expect(result).to eq(expected)
  end

  it 'reads classes' do
    binary = parse_bin('44 41 42 00 03 00 00 00 00 00 00 00 00 00 00 00
                        e8 00 00 00 00 00 00 00 ab 00 00 00 00 00 00 00
                        06 00 00 00 00 00 00 00 64 61 74 61 00 00 00 00
                        00 00 00 00 00 00 00 00 e8 00 00 00 00 00 00 00
                        07 00 00 00 00 00 00 00 63 6f 64 65 00 00 00 00
                        00 00 00 00 00 00 00 00 ef 00 00 00 00 00 00 00
                        43 00 00 00 00 00 00 00 63 6c 61 73 00 00 00 00
                        00 00 00 00 00 00 00 00 32 01 00 00 00 00 00 00
                        0c 00 00 00 00 00 00 00 73 79 6d 64 00 00 00 00
                        00 00 00 00 00 00 00 00 3e 01 00 00 00 00 00 00
                        15 00 00 00 00 00 00 00 73 79 6d 62 00 00 00 00
                        00 00 00 00 00 00 00 00 53 01 00 00 00 00 00 00
                        28 00 00 00 00 00 00 00 66 75 6e 63 00 00 00 00
                        00 00 00 00 00 00 00 00 7b 01 00 00 00 00 00 00
                        18 00 00 00 00 00 00 00 66 6f 6f 62 61 72 00 00
                        26 00 00 0d 00 00 00 01 1c 01 00 00 00 04 00 00
                        1c 02 00 01 00 02 00 00 1e ff ff 00 01 02 00 20
                        ff ff 26 00 00 11 00 00 e8 00 00 00 00 00 00 00
                        06 00 00 00 00 00 00 00 1e ff ff 00 01 00 00 20
                        ff ff 00 01 00 00 01 00 01 01 00 00 00 00 42 61
                        72 00 46 6f 6f 00 62 61 72 00 6d 61 69 6e 00 6e
                        65 77 00 3e 01 00 00 00 00 00 00 42 01 00 00 00
                        00 00 00 46 01 00 00 00 00 00 00 4a 01 00 00 00
                        00 00 00 4f 01 00 00 00 00 00 00 03 00 01 01 f0
                        00 00 00 00 00 00 00 02 00 00 01 12 01 00 00 00
                        00 00 00                                       ')

    result = DabBinReader.new.parse_dab_binary(binary)

    expected = {
      header: {
        dab: 'DAB',
        zero: 0,
        version: 3,
        offset: 0,
        size_of_header: 232,
        size_of_data: 171,
        sections_count: 6,
        sections: [
          {name: 'data', zero1: 0, zero2: 0, zero3: 0, address: 232, length: 7},
          {name: 'code', zero1: 0, zero2: 0, zero3: 0, address: 239, length: 67},
          {name: 'clas', zero1: 0, zero2: 0, zero3: 0, address: 306, length: 12},
          {name: 'symd', zero1: 0, zero2: 0, zero3: 0, address: 318, length: 21},
          {name: 'symb', zero1: 0, zero2: 0, zero3: 0, address: 339, length: 40},
          {name: 'func', zero1: 0, zero2: 0, zero3: 0, address: 379, length: 24},
        ],
      },
      symbols: %w[Bar Foo bar main new],
      functions: [
        {symbol: 'main', klass: 'Bar', address: 240},
        {symbol: 'bar', klass: 'Foo', address: 274},
      ],
      all_symbols: %w[Bar Foo bar main new],
      klasses: [
        {index: 256, parent_index: 0, symbol: 'Foo'},
        {index: 257, parent_index: 0, symbol: 'Bar'},
      ],
    }

    expect(result).to eq(expected)
  end
end

class DabBinReader
  def initialize
    @klasses = nil
  end

  def parse_ring(filename, symbols, extra_offset = 0)
    text = File.binread(filename)

    data = parse_dab_binary(text, symbols)

    unit = DabNodeUnit.new

    unit.start_offset = text.length + extra_offset

    index = 0

    # errap data

    data[:symbols].each do |symbol|
      node = DabNodeSymbol.new(symbol)
      node.source_ring = filename
      node.source_ring_index = index + symbols.count
      index += 1
      unit.add_constant(node)
    end

    data[:klasses]&.each do |klass|
      # :klasses => [
      # [0] {
      #            :index => 256,
      #     :parent_index => 0,
      #           :symbol => "Postgres"
      # }
      parent_klass = unit.find_or_define_class(klass[:parent_index])
      # errap [klass,parent_klass,parent_klass.identifier]
      parent = parent_klass.identifier
      node = DabNodeClassDefinition.new(klass[:symbol], parent, [])
      unit.add_class(node, forced_number: klass[:index])
    end

    data[:functions].each do |function|
      name = function[:symbol]
      arglist = nil
      node = DabNodeFunctionStub.new(name, arglist, is_static: function[:static])
      if function[:klass].nil?
        unit.add_function(node)
      else
        klass = unit.find_or_define_class(function[:klass])
        klass.add_function(node)
      end
    end

    [unit, data[:symbols]]
  end

  def parse_header(string)
    data = string.unpack('a3CL<Q<Q<Q<Q<')
    %i[dab zero version offset size_of_header size_of_data sections_count].zip(data).to_h
  end

  def parse_section(string)
    data = string.unpack('a4L<L<L<Q<Q<')
    %i[name zero1 zero2 zero3 address length].zip(data).to_h
  end

  def parse_whole_header(string)
    header = parse_header(string[0..40])
    sections = []
    sections_count = header[:sections_count]
    sections_count.times do |i|
      offset = i * 32
      range = ((40 + offset)..(72 + offset))
      data = string[range]
      sections << parse_section(data)
    end
    header[:sections] = sections
    header
  end

  def parse_symbols(symd, symd_start, symb, base_offset)
    count = symb.length / 8
    addresses = symb.unpack("Q<#{count}")
    addresses.map do |address|
      offset = address - symd_start - base_offset
      symd.unpack("@#{offset}Z*").first
    end
  end

  def parse_klasses(clas, symbols)
    # klass_length = 2 + 2 + 2
    # count = clas.length / klass_length
    offset = 0
    ret = []
    loop do # Array.new(count) do |n|
      # offset = n * klass_length
      # STDERR.puts "read class index = #{offset}"
      data = clas.unpack("@#{offset}S<S<S<S<")
      offset += 8
      klass = %i[index parent_index symbol templateargsn].zip(data).to_h
      # ap klass
      klass[:templateargs] = (0...klass[:templateargsn]).map do
        v = clas.unpack("@#{offset}S<")
        offset += 2
        v
      end
      klass[:symbol] = symbols[klass[:symbol]]
      ret << klass

      break if offset == clas.length
    end
    ret
  end

  def parse_extended_functions(fext, symbols)
    length = fext.length
    pos = 0

    ret = []

    while pos < length
      # warn "read_ext_fun(#{pos} :: #{length})"

      data = fext.unpack("@#{pos}S<S<Q<S<Q<C")
      fun = %i[symbol klass address arg_count length flags].zip(data).to_h
      fun[:klass] = lookup_klass(fun[:klass])
      fun[:symbol] = symbols[fun[:symbol]]
      fun[:static] = !!(fun[:flags] & METHOD_FLAGS[:static] == METHOD_FLAGS[:static])
      pos += 2 + 2 + 8 + 2 + 8 + 1
      fun[:args] = Array.new((fun[:arg_count] + 1)) do
        data2 = fext.unpack("@#{pos}S<S<")
        pos += 4
        arg = %i[symbol klass].zip(data2).to_h
        arg[:klass] = lookup_klass(arg[:klass])
        arg[:symbol] = symbols[arg[:symbol]]
        arg
      end
      fun.delete(:arg_count)
      fun[:ret] = fun[:args].pop
      fun[:ret].delete(:symbol)
      ret << fun
    end

    ret
  end

  def get_section(binary, header, section_name)
    header[:sections].each do |section|
      next unless section[:name] == section_name

      a = section[:address]
      b = a + section[:length]
      return binary[a...b]
    end
    nil
  end

  def parse_whole_header_with_offset(binary)
    data = parse_whole_header(binary)
    data[:sections].each do |section|
      section[:address] -= data[:offset]
    end
    data
  end

  def parse_dab_binary(binary, start_symbols = [])
    header = parse_whole_header_with_offset(binary)

    # warn header.ai

    symb = get_section(binary, header, 'symb')
    fext = get_section(binary, header, 'fext')

    base_offset = header[:offset]

    symbols = parse_symbols(binary, 0, symb, base_offset)

    all_symbols = start_symbols + symbols

    clas = get_section(binary, header, 'clas')
    @klasses = parse_klasses(clas, all_symbols) if clas

    functions = parse_extended_functions(fext, all_symbols) if fext

    {
      header: header,
      symbols: symbols,
      functions: functions,
      all_symbols: all_symbols,
      klasses: @klasses,
    }.compact
  end

  def lookup_klass(klass)
    return nil if klass == 65535

    if klass >= USER_CLASSES_OFFSET
      raise NotImplementedError.new('no user classes loaded') unless @klasses

      return @klasses.detect { |data| data[:index] == klass }[:symbol]
    end
    STANDARD_CLASSES[klass]
  end
end

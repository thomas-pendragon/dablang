class DabBinReader
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

  def parse_symbols(symd, symd_start, symb)
    count = symb.length / 8
    addresses = symb.unpack("Q<#{count}")
    addresses.map do |address|
      offset = address - symd_start
      symd.unpack("@#{offset}Z*").first
    end
  end

  def parse_functions(func, symbols)
    fun_length = 2 + 2 + 8
    count = func.length / fun_length
    Array.new(count) do |n|
      offset = n * fun_length
      data = func.unpack("@#{offset}S<S<Q<")
      fun = %i[symbol klass address].zip(data).to_h
      {
        symbol: symbols[fun[:symbol]],
        klass: lookup_klass(fun[:klass]),
        address: fun[:address],
      }
    end
  end

  def parse_klasses(clas, symbols)
    klass_length = 2 + 2 + 2
    count = clas.length / klass_length
    Array.new(count) do |n|
      offset = n * klass_length
      data = clas.unpack("@#{offset}S<S<S<")
      klass = %i[index parent_index symbol].zip(data).to_h
      klass[:symbol] = symbols[klass[:symbol]]
      klass
    end
  end

  def lookup_klass(klass)
    return nil if klass == 65535
    raise NotImplementedError.new('no user class lookup yet') if klass >= USER_CLASSES_OFFSET
    STANDARD_CLASSES[klass]
  end
end

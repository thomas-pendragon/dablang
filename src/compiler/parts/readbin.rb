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
      ring_signature = {
        arguments: function.fetch(:args).map do |argument|
          {
            name: argument.fetch(:symbol).dup.freeze,
            type: argument.fetch(:klass).dup.freeze,
          }.freeze
        end.freeze,
        return_type: function.fetch(:ret).fetch(:klass).dup.freeze,
      }.freeze
      node = DabNodeFunctionStub.new(
        name,
        arglist,
        is_static: function[:static],
        ring_signature: ring_signature
      )
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
    raise ArgumentError.new('truncated symbol table') unless (symb.length % 8).zero?

    count = symb.length / 8
    addresses = symb.unpack("Q<#{count}")
    artifact_start = symd_start + base_offset
    addresses.each_with_index.map do |address, index|
      if address < artifact_start
        raise ArgumentError.new("symbol reference #{index} starts before the artifact")
      end

      offset = address - artifact_start
      if offset >= symd.bytesize
        raise ArgumentError.new("symbol reference #{index} is outside the artifact")
      end

      terminator = symd.index("\0", offset)
      unless terminator
        raise ArgumentError.new("symbol #{index} is not NUL-terminated within the artifact")
      end

      symd.byteslice(offset, terminator - offset)
    end
  end

  def parse_klasses(clas, symbols)
    parse_klasses_with_template_arguments(clas, symbols) || parse_legacy_klasses(clas, symbols)
  end

private

  def parse_klasses_with_template_arguments(clas, symbols)
    offset = 0
    ret = []
    while offset < clas.length
      return nil if clas.length - offset < 8 && ret.empty?
      raise ArgumentError.new('truncated class table') if clas.length - offset < 8

      data = clas.unpack("@#{offset}S<S<S<S<")
      offset += 8
      klass = %i[index parent_index symbol templateargsn].zip(data).to_h
      templateargs_length = klass[:templateargsn] * 2
      return nil if clas.length - offset < templateargs_length && ret.empty?
      raise ArgumentError.new('truncated class table') if clas.length - offset < templateargs_length

      templateargs = Array.new(klass[:templateargsn]) do
        value = clas.unpack("@#{offset}S<").first
        offset += 2
        value
      end
      klass[:symbol] = symbols[klass[:symbol]]
      klass[:templateargs] = templateargs unless templateargs.empty?
      klass.delete(:templateargsn)
      ret << klass
    end
    ret
  end

  def parse_legacy_klasses(clas, symbols)
    klass_length = 2 + 2 + 2
    raise ArgumentError.new('truncated class table') unless (clas.length % klass_length).zero?

    count = clas.length / klass_length
    Array.new(count) do |index|
      offset = index * klass_length
      data = clas.unpack("@#{offset}S<S<S<")
      klass = %i[index parent_index symbol].zip(data).to_h
      klass[:symbol] = symbols[klass[:symbol]]
      klass
    end
  end

public

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

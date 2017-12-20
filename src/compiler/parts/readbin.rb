class DabBinReader
  def parse_header(string)
    data = string.unpack('a3CL<Q<Q<Q<')
    %i[dab zero version size_of_header size_of_data sections_count].zip(data).to_h
  end

  def parse_section(string)
    data = string.unpack('a4L<L<L<Q<Q<')
    %i[name zero1 zero2 zero3 address length].zip(data).to_h
  end

  def parse_whole_header(string)
    header = parse_header(string[0..32])
    sections = []
    sections_count = header[:sections_count]
    sections_count.times do |i|
      offset = i * 32
      range = ((32 + offset)..(64 + offset))
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
end

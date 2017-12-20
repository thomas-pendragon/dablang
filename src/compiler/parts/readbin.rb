class DabBinReader
  def parse_header(string)
    data = string.unpack('a3CL<Q<Q<Q<')
    %i[dab zero version size_of_header size_of_data sections_count].zip(data).to_h
  end

  def parse_section(string)
    data = string.unpack('a4L<L<L<Q<Q<')
    %i[name zero1 zero2 zero3 address length].zip(data).to_h
  end
end

class DabBinReader
  def parse_header(string)
    data = string.unpack('a3CL<Q<Q<Q<')
    %i[dab zero version size_of_header size_of_data sections_count].zip(data).to_h
  end
end

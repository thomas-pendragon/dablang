class DabCompiler
  def initialize(stream)
    @stream = stream
  end

  def program
    context = DabContext.new(@stream)
    context.read_program
  rescue DabEndOfStreamError
    ret = DabNodeUnit.new
    source = SourceString.new('', @stream.filename, 0, 0, 0)
    ret.add_error(DabUnexpectedEOFError.new(source))
    ret
  end
end

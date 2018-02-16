class DabCompiler
  def initialize(stream)
    @stream = stream
  end

  def program(classes = [])
    context = DabContext.new(@stream, :top)
    classes.each do |klass|
      context.add_class(klass)
    end
    return context.read_program
  rescue UnknownTokenException
    ret = DabNodeUnit.new
    source = SourceString.new('', @stream.filename, 0, 0, 0)
    ret.add_error(DabUnknownTokenError.new(source))
    return ret
  rescue SelfOutsideException => e
    ret = DabNodeUnit.new
    ret.add_error(DabCompileSelfOutsideInstanceContextError.new(e.node))
    return ret
  rescue DabEndOfStreamError
    ret = DabNodeUnit.new
    source = SourceString.new('', @stream.filename, 0, 0, 0)
    ret.add_error(DabUnexpectedEOFError.new(source))
    return ret
  end
end

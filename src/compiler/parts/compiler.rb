class DabCompiler
  def initialize(stream)
    @stream = stream
  end

  def program(classes = [], parent_unit: nil)
    context = DabContext.new(@stream, :top)
    classes.each do |klass|
      context.add_class(klass)
    end
    context.read_program(parent_unit)
  rescue UnknownTokenException
    ret = DabNodeUnit.new
    source = SourceString.new('', @stream.filename, 0, 0, 0)
    ret.add_error(DabUnknownTokenError.new(source))
    ret
  rescue SelfOutsideException => e
    ret = DabNodeUnit.new
    ret.add_error(DabCompileSelfOutsideInstanceContextError.new(e.node))
    ret
  rescue DabEndOfStreamError
    ret = DabNodeUnit.new
    source = SourceString.new('', @stream.filename, 0, 0, 0)
    ret.add_error(DabUnexpectedEOFError.new(source))
    ret
  end
end

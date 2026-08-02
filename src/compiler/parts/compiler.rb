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
    ret.add_error(DabUnknownTokenError.new(fallback_source))
    ret
  rescue SelfOutsideException => e
    ret = DabNodeUnit.new
    ret.add_error(DabCompileSelfOutsideInstanceContextError.new(e.node))
    ret
  rescue DabEndOfStreamError
    ret = DabNodeUnit.new
    ret.add_error(DabUnexpectedEOFError.new(fallback_source))
    ret
  end

private

  def fallback_source
    span = DabSourceSpan.point(source_unit: @stream.source_unit, offset: 0, line: 0, column: 0)
    SourceString.new('', span)
  end
end

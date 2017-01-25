class DabCompiler
  def initialize(stream)
    @stream = stream
  end

  def program
    context = DabContext.new(@stream)
    context.read_program
  end
end

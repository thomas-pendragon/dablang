class DabCompilerError < RuntimeError
  attr_reader :source
  def initialize(message, source)
    super(message)
    @source = source    
  end
end

class DabCompileUnknownFunctionError < DabCompilerError
  def initialize(function, source)
    super("Unknown function <#{function}>.", source)
  end
  def error_code
    1
  end
end

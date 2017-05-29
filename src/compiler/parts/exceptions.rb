class DabCompilerError
  attr_reader :message
  attr_reader :source
  attr_reader :source_infos
  def initialize(message, source)
    @message = message
    @source = source
    @source_infos = []
  end

  def add_source_info(node, info)
    @source_infos << [node, info]
  end

  def annotated_source(stream)
    return '' unless source.source_line >= 0
    stream.annotated_node(source)
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

class DabCompileSetvarTypeError < DabCompilerError
  def initialize(type1, type2, source)
    super("Cannot assign <#{type1.type_string}> to a variable of type <#{type2.type_string}>.", source)
  end

  def error_code
    2
  end
end

class DabCompileSetargTypeError < DabCompilerError
  def initialize(type1, type2, source)
    super("Cannot pass <#{type1.type_string}> to an argument of type <#{type2.type_string}>.", source)
  end

  def error_code
    3
  end
end

class DabUnexpectedEOFError < DabCompilerError
  def initialize(source)
    super('Unexpected end of file.', source)
  end

  def error_code
    4
  end
end

class DabCompileCallArgCountError < DabCompilerError
  def initialize(func, actual, expected, source)
    super("Incorrect number of arguments in <#{func}> call; got #{actual}, expected #{expected}.", source)
  end

  def error_code
    5
  end
end

class DabUnknownTokenError < DabCompilerError
  def initialize(source)
    super('Unknown token.', source)
  end

  def error_code
    6
  end
end

class DabCompileMultipleDefinitionsError < DabCompilerError
  def initialize(id, source)
    super("Multiple definitions of <#{id}>.", source)
  end

  def error_code
    7
  end
end

class DabCompileSelfOutsideInstanceContextError < DabCompilerError
  def initialize(source)
    super('self outside instance context.', source)
  end

  def error_code
    8
  end
end

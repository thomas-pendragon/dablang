require_relative 'node'

class DabNodeInstanceVarProxy < DabNode
  lower_with Uncomplexify

  def initialize(selfnode, idnode)
    super()
    insert(selfnode)
    insert(idnode)
  end

  def node_self
    @children[0]
  end

  def node_identifier
    @children[1]
  end

  def uncomplexify_args
    [node_self]
  end

  def accepts?(arg)
    arg.register?
  end

  def identifier
    "@#{node_identifier.extra_value}"
  end

  def compile_as_ssa(output, output_register)
    self_register = node_self.input_register
    output.comment(identifier)
    output.printex(self, 'GET_INSTVAR_EXT', "R#{output_register}", "S#{node_identifier.symbol_index}", "R#{self_register}")
  rescue StandardError
    root.dump
    raise
  end
end

class DabNodeInstanceVar < DabNode
  def initialize(identifier)
    super()
    insert(identifier[1..-1])
  end

  def node_identifier
    @children[0]
  end

  def identifier
    "@#{node_identifier.extra_value}"
  end

  def extra_dump
    identifier
  end

  def compile_as_ssa(output, output_register)
    output.comment(identifier)
    output.printex(self, 'GET_INSTVAR', "R#{output_register}", "S#{node_identifier.symbol_index}")
  end

  def compile(output)
    output.push(node_identifier)
    output.print('PUSH_INSTVAR')
  end

  def formatted_source(_options)
    extra_dump
  end

  def use_self_proxy!
    replace_with!(DabNodeInstanceVarProxy.new(DabNodeClosureSelf.new, node_identifier))
  end
end

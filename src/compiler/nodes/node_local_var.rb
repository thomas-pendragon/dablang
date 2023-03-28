require_relative 'node'
require_relative '../concerns/localvar_definition_concern'

class DabNodeUnbox < DabNode
  lower_with Uncomplexify

  def initialize(inner)
    super()
    insert(inner)
  end

  def value
    self[0]
  end

  def uncomplexify_args
    [value]
  end

  def compile_as_ssa(output, output_register)
    input_register = value.input_register
    output.printex(self, 'UNBOX', "R#{output_register}", "R#{input_register}")
  end
end

class DabNodeLocalVar < DabNode
  box_with :unbox

  include LocalvarDefinitionConcern

  attr_accessor :identifier
  attr_reader :original_identifier

  def initialize(identifier)
    super()
    @identifier = identifier
    @original_identifier = identifier
  end

  def extra_dump
    ret = "<#{real_identifier}> [#{index}]"
    if @unboxed
      ret += ' [_box]'
    else
      if boxed?
        ret += ' [BOXED]'.purple
      end
      if closure_pass?
        ret += ' [CLOSURE PASS]'.purple
      end
    end
    ret
  end

  def unbox
    return false unless boxed?
    return false if @unboxed
    return false if closure_pass?

    @unboxed = true

    replace_with!(DabNodeUnbox.new(self.dup))

    true
  end

  def real_identifier
    identifier
  end

  def formatted_source(_options)
    original_identifier
  end

  def var_setters
    previous_nodes_in_tree(DabNodeSetLocalVar)&.select do |node|
      node.identifier == self.identifier
    end
  end

  def last_var_setter
    var_setters.last
  end

  def register?
    true
  end
end

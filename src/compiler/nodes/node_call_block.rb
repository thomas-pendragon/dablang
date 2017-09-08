require_relative 'node.rb'

class DabNodeCallBlock < DabNode
  def initialize(body, arglist = nil)
    super()
    insert(body, 'body')
    insert(arglist, 'arglist') if arglist
  end

  def body
    self[0]
  end

  def arglist
    self[1]
  end

  def formatted_source(options)
    ret = ' ^'
    if arglist&.count
      ret += '('
      ret += arglist.map { |arg| arg.formatted_source(options) }.join(', ')
      ret += ')'
    end
    ret += ' {'
    ret += "\n"
    ret += _indent(body.formatted_source(options))
    ret + '}'
  end

  def captured_variables
    all_getters = all_nodes(DabNodeLocalVar)
    all_getter_definitions = all_getters.map(&:var_definition).compact.uniq
    all_defines = all_nodes(DabNodeDefineLocalVar)

    all_getter_definitions - all_defines
  end
end

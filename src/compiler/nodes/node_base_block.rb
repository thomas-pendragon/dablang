require_relative 'node'

class DabNodeBaseBlock < DabNode
  def initialize(body, arglist = nil)
    super()
    insert(body)
    insert(arglist) if arglist
  end

  def children_info
    {
      body => 'body',
      arglist => 'arglist',
    }
  end

  def body
    self[0]
  end

  def arglist
    self[1]
  end

  def formatted_source(options)
    ret = '^'
    if arglist&.count
      ret += '('
      ret += arglist.map { |arg| arg.formatted_source(options) }.join(', ')
      ret += ')'
    end
    ret += ' {'
    ret += "\n"
    ret += _indent(body.formatted_source(options))
    "#{ret}}"
  end

  def captured_variables
    all_getters = all_nodes(DabNodeLocalVar)
    all_getter_definitions = all_getters.map(&:var_definition).compact.uniq
    all_defines = all_nodes(DabNodeDefineLocalVar)

    list = all_getter_definitions - all_defines

    list.reject { |it| captured_writable_variables.map(&:var_definition).include?(it.var_definition) }
  end

  def captured_writable_variables
    all_defines = all_nodes(DabNodeDefineLocalVar)

    all_nodes(DabNodeSetLocalVar)
      .select(&:setter_only?)
      .reject { |it| all_defines.include?(it.var_definition) }
  end
end

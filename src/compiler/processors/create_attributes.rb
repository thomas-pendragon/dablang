class CreateAttributes
  def run(node)
    body = DabNodeTreeBlock.new

    node.functions.each do |function|
      function.create_attribute_init(body)
    end

    func = DabNodeFunction.new("__init_#{node.root.start_offset}", body, nil, false)
    node.add_function(func)
    func.run_init!
  end
end

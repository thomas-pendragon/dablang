class CreateAttributes
  def run(node)
    return unless $feature_attributes

    body = DabNodeTreeBlock.new

    node.functions.each do |function|
      function.create_attribute_init(body)
    end

    func = DabNodeFunction.new('__init', body, nil, false)
    node.add_function(func)
    func.init!
  end
end

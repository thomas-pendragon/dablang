class Object
  def presence
    self
  end
end

class String
  def presence
    return nil if self == ''

    super
  end
end

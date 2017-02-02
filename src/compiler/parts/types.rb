class DabType
  def self.parse(typename)
    return DabTypeAny.new if typename.nil?
    return DabTypeString.new if typename == 'String'
    raise "Unknown type #{typename}"
  end

  def can_assign_from?(_other_type)
    false
  end
end

class DabTypeAny < DabType
  def type_string
    'Any'
  end

  def can_assign_from?(_other_type)
    true
  end
end

class DabTypeString < DabType
  def type_string
    'String'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeString
  end
end

class DabTypeFixnum < DabType
  def type_string
    'Fixnum'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeFixnum
  end
end

class DabType
  def self.parse(typename)
    return DabTypeAny.new if typename.nil?
    return DabTypeString.new if typename == 'String'
    raise "Unknown type #{typename}"
  end

  def can_assign_from?(_other_type)
    false
  end

  def concrete?
    false
  end

  def belongs?(_value)
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

  def belongs?(value)
    value.is_a? String
  end
end

class DabTypeLiteralString < DabTypeString
  def type_string
    'LiteralString'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeLiteralString
  end

  def concrete?
    true
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

class DabTypeSymbol < DabType
  def type_string
    'Symbol'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeSymbol
  end
end

class DabTypeArray < DabTypeString
  def type_string
    'Array'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeArray
  end
end

class DabTypeNil < DabType
  def type_string
    'NilClass'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeNil
  end
end

class DabType
  def self.parse(typename)
    return DabTypeObject.new if typename.nil?
    return DabTypeString.new if typename == 'String'
    return DabTypeFixnum.new if typename == 'Fixnum'
    return DabTypeLiteralFixnum.new if typename == 'LiteralFixnum'
    return DabTypeUint8.new if typename == 'Uint8'
    return DabTypeInt32.new if typename == 'Int32'
    raise "Unknown type #{typename}"
  end

  def can_assign_from?(_other_type)
    false
  end

  def requires_cast?(_other_type)
    false
  end

  def concrete?
    false
  end

  def belongs?(_value)
    false
  end
end

class DabTypeObject < DabType
  def type_string
    'Object'
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
    other_type.is_a?(DabTypeString) || other_type.is_a?(DabTypeNil)
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
    other_type.is_a?(DabTypeFixnum) || other_type.is_a?(DabTypeObject)
  end
end

class DabTypeClass < DabType
  def type_string
    'Class'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeClass
  end

  def concrete?
    true
  end
end

class DabTypeLiteralFixnum < DabTypeFixnum
  def type_string
    'LiteralFixnum'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeLiteralFixnum
  end

  def concrete?
    true
  end
end

class DabTypeUint8 < DabTypeFixnum
  def type_string
    'Uint8'
  end

  def can_assign_from?(other_type)
    other_type.is_a? DabTypeFixnum
  end

  def requires_cast?(other_type)
    can_assign_from?(other_type) && !(other_type.is_a? DabTypeUint8)
  end

  def concrete?
    true
  end
end

class DabTypeInt32 < DabTypeFixnum
  def type_string
    'Int32'
  end

  def can_assign_from?(other_type)
    other_type.is_a?(DabTypeFixnum) || other_type.is_a?(DabTypeObject)
  end

  def requires_cast?(other_type)
    can_assign_from?(other_type) && !(other_type.is_a? DabTypeInt32)
  end

  def concrete?
    true
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

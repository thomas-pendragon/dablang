class DabType
  def self.parse(typename)
    return DabTypeObject.new if typename.nil?
    return DabTypeString.new if typename == 'String'
    return DabTypeFixnum.new if typename == 'Fixnum'
    return DabTypeUint.new(8) if typename == 'Uint8'
    return DabTypeUint.new(16) if typename == 'Uint16'
    return DabTypeUint.new(32) if typename == 'Uint32'
    return DabTypeUint.new(64) if typename == 'Uint64'
    return DabTypeInt32.new if typename == 'Int32'
    return DabTypeIntPtr.new if typename == 'IntPtr'
    return DabTypeNil.new if typename == 'NilClass'
    raise "Unknown type #{typename}"
  end

  def can_assign_from?(other_type)
    other_type.base_type.is_a?(self.class) || other_type.base_type.is_a?(DabTypeNil) || other_type.base_type.is_a?(DabTypeObject)
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

  def has_function?(identifier)
    return true if identifier == 'class'
    return true if identifier == 'to_s'
    false
  end

  def base_type
    self
  end

  def real_type_string
    type_string
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

  def belongs?(value)
    value.is_a? String
  end

  def has_function?(identifier)
    return true if identifier == '[]'
    return true if identifier == 'upcase'
    super
  end
end

class DabTypeFixnum < DabType
  def type_string
    'Fixnum'
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

  def has_function?(identifier)
    return true if identifier == 'new'
    super
  end
end

class DabTypeIntPtr < DabType
  def type_string
    'IntPtr'
  end

  def can_assign_from?(other_type)
    other_type.is_a?(DabTypeIntPtr) || super
  end

  def concrete?
    true
  end
end

class DabTypeUint < DabTypeFixnum
  def initialize(size)
    @size = size
  end

  def type_string
    "Uint#{@size}"
  end

  def can_assign_from?(other_type)
    other_type.base_type.is_a?(DabTypeFixnum) || super
  end

  def requires_cast?(other_type)
    can_assign_from?(other_type) && !(other_type.base_type.is_a? self.class)
  end

  def concrete?
    true
  end
end

class DabTypeInt32 < DabTypeFixnum
  def type_string
    'Int32'
  end

  def requires_cast?(other_type)
    can_assign_from?(other_type) && !(other_type.base_type.is_a? DabTypeInt32)
  end

  def can_assign_from?(other_type)
    other_type.base_type.is_a?(DabTypeFixnum) || super
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

class DabTypeArray < DabType
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

  def concrete?
    true
  end
end

class DabConcreteType < DabType
  def initialize(base)
    @base = base
  end

  def base_type
    @base
  end

  def type_string
    @base.type_string
  end

  def real_type_string
    type_string + '!'
  end

  def can_assign_from?(other_type)
    @base.can_assign_from?(other_type)
  end

  def requires_cast?(other_type)
    @base.requires_cast?(other_type)
  end

  def concrete?
    true
  end

  def has_function?(identifier)
    @base.has_function?(identifier)
  end
end

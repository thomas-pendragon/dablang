class TypedNumber
  attr_reader :value
  attr_reader :type

  def initialize(value, type)
    @type = type.downcase
    @unsigned = !!type['uint']
    @length = @type.gsub(/u?int/, '').to_i
    @value = value
    _fix!
  end

  def +(other)
    # TODO: test types
    TypedNumber.new(@value + other.value, @type)
  end

  def ==(other)
    case other
    when Fixnum
      value == other
    when TypedNumber
      value == other.value
    else
      raise "cannot compare TypedNumber with #{other.class}"
    end
  end

  def _fix! # TODO: signed support
    max = 2**@length
    @value %= max
  end

  def to_s
    "#{@value} [#{type}]"
  end
end

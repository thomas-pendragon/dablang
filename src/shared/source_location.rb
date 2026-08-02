require_relative 'source_unit'

class DabSourceLocationError < ArgumentError
end

class DabSourceLocation
  attr_reader :source_unit, :offset, :line, :column

  def initialize(source_unit:, offset:, line:, column:)
    @source_unit = DabSourceUnit.validate(source_unit)
    @offset = validate_coordinate(offset, 'offset')
    @line = validate_coordinate(line, 'line')
    @column = validate_coordinate(column, 'column')
    freeze
  end

  def filename
    source_unit.filename
  end

  def to_h
    {offset: offset, line: line, column: column}
  end

private

  def validate_coordinate(value, name)
    unless value.is_a?(Integer) && value >= 0
      raise DabSourceLocationError.new("invalid source #{name}; expected a non-negative Integer")
    end

    value
  end
end

class DabSourceSpan
  attr_reader :start_location, :end_location

  def initialize(start_location:, end_location:)
    @start_location = validate_location(start_location)
    @end_location = validate_location(end_location)
    unless @start_location.source_unit.equal?(@end_location.source_unit)
      raise DabSourceLocationError.new('source span locations must share one DabSourceUnit identity')
    end
    if @end_location.offset < @start_location.offset
      raise DabSourceLocationError.new('source span end offset must not precede its start offset')
    end

    freeze
  end

  def self.point(source_unit:, offset:, line:, column:)
    location = DabSourceLocation.new(source_unit: source_unit, offset: offset, line: line, column: column)
    new(start_location: location, end_location: location)
  end

  def self.validate(span)
    return span if span.is_a?(self)

    raise DabSourceLocationError.new('invalid source span; expected a DabSourceSpan')
  end

  def source_unit
    start_location.source_unit
  end

  def filename
    source_unit.filename
  end

  def start_offset
    start_location.offset
  end

  def end_offset
    end_location.offset
  end

private

  def validate_location(location)
    return location if location.is_a?(DabSourceLocation)

    raise DabSourceLocationError.new('invalid source location; expected a DabSourceLocation')
  end
end

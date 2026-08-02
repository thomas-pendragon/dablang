require_relative 'syntax_profile'

class DabSourceUnitError < ArgumentError
end

class DabSourceUnit
  attr_reader :input, :filename, :syntax_profile

  def initialize(input:, syntax_profile:, filename: nil)
    unless input == :stdin || input.is_a?(String)
      raise DabSourceUnitError.new('invalid Dab source unit input; expected :stdin or a filename String')
    end

    @input = input.is_a?(String) ? input.dup.freeze : input
    @filename = (filename || default_filename).dup.freeze
    @syntax_profile = DabSyntaxProfile.validate(syntax_profile)
    freeze
  end

  def self.validate(source_unit)
    return source_unit if source_unit.is_a?(self)

    raise DabSourceUnitError.new('invalid Dab source unit; expected a DabSourceUnit')
  end

  def require_parser_support!
    syntax_profile.require_parser_support!
    self
  end

private

  def default_filename
    input == :stdin ? '<input>' : input
  end
end

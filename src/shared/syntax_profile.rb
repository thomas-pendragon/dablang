class DabSyntaxProfileError < ArgumentError
end

class DabUnsupportedSyntaxProfileError < DabSyntaxProfileError
end

class DabSyntaxProfile
  attr_reader :name

  def initialize(name)
    @name = name.freeze
    freeze
  end

  LEGACY = new('legacy')
  MODERN = new('modern')
  PROFILES = [LEGACY, MODERN].freeze
  PROFILES_BY_NAME = PROFILES.map { |profile| [profile.name, profile] }.to_h.freeze

  private_class_method :new

  def self.fetch(name)
    unless name.is_a?(String)
      raise DabSyntaxProfileError.new('invalid Dab syntax profile name; expected a String')
    end

    profile = PROFILES_BY_NAME[name]
    return profile if profile

    raise DabSyntaxProfileError.new("unknown Dab syntax profile #{name.inspect}; available profiles: #{PROFILES_BY_NAME.keys.join(', ')}")
  end

  def self.validate(profile)
    return profile if PROFILES.any? { |known| known.equal?(profile) }

    raise DabSyntaxProfileError.new('invalid Dab syntax profile; expected a registered DabSyntaxProfile')
  end

  def self.available
    PROFILES
  end

  def require_parser_support!
    return self if equal?(LEGACY)

    raise DabUnsupportedSyntaxProfileError.new(
      "unsupported Dab syntax profile #{name.inspect}: parser is not implemented"
    )
  end

  def ==(other)
    other.is_a?(DabSyntaxProfile) && other.name == name
  end

  alias eql? ==

  def hash
    [self.class, name].hash
  end

  def to_s
    name
  end
end

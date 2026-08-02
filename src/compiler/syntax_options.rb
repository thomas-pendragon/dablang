class DabCompilerSyntaxOptionError < ArgumentError
end

module DabCompilerSyntaxOptions
  def self.parse(arguments)
    syntax_options = arguments.select do |argument|
      argument == '--syntax' || argument.start_with?('--syntax=')
    end

    if syntax_options.length > 1
      raise DabCompilerSyntaxOptionError.new('--syntax may be specified at most once')
    end

    syntax_option = syntax_options.first
    return [DabSyntaxProfile::LEGACY, arguments.dup, false] unless syntax_option

    unless syntax_option.start_with?('--syntax=')
      raise DabCompilerSyntaxOptionError.new('--syntax requires the --syntax=PROFILE spelling')
    end

    syntax_profile = DabSyntaxProfile.fetch(syntax_option.split('=', 2).last)
    [syntax_profile, arguments.reject { |argument| argument == syntax_option }, true]
  rescue DabSyntaxProfileError => e
    raise DabCompilerSyntaxOptionError.new(e.message)
  end

  def self.resolve(syntax_profile:, explicit:, inputs:)
    syntax_profile = DabSyntaxProfile.validate(syntax_profile)
    return syntax_profile if explicit

    infer_from_filenames(inputs) || syntax_profile
  end

  def self.infer_from_filenames(inputs)
    profiles = Array(inputs).filter_map { |input| profile_for_filename(input) }.uniq
    if profiles.length > 1
      names = profiles.map(&:name).sort.join(', ')
      raise DabCompilerSyntaxOptionError.new(
        "input filenames select multiple Dab syntax profiles: #{names}; use --syntax=PROFILE to select one explicitly"
      )
    end

    profiles.first
  end

  def self.profile_for_filename(filename)
    return unless filename.is_a?(String)
    return DabSyntaxProfile::LEGACY if File.extname(filename) == '.dab'
    return DabSyntaxProfile::MODERN if File.extname(filename) == '.dabm'

    nil
  end
end

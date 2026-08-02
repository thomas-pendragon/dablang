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
    return [DabSyntaxProfile::LEGACY, arguments.dup] unless syntax_option

    unless syntax_option.start_with?('--syntax=')
      raise DabCompilerSyntaxOptionError.new('--syntax requires the --syntax=PROFILE spelling')
    end

    syntax_profile = DabSyntaxProfile.fetch(syntax_option.split('=', 2).last)
    [syntax_profile, arguments.reject { |argument| argument == syntax_option }]
  rescue DabSyntaxProfileError => e
    raise DabCompilerSyntaxOptionError.new(e.message)
  end
end

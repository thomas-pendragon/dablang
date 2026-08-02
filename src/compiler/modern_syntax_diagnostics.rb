require_relative '../shared/source_location'

class DabModernSyntaxDiagnosticError < DabUnsupportedSyntaxProfileError
  attr_reader :source_location

  def initialize(message, source_location:)
    @source_location = source_location
    super(message)
  end

  def diagnostic
    filename = source_location.filename.tr('\\', '/')
    "#{filename}:#{source_location.line}:#{source_location.column}: error: #{message}"
  end
end

module DabModernSyntaxDiagnostics
module_function

  def validate_source_units!(source_units, ring_bases: [])
    source_units.each do |source_unit|
      begin
        source_unit.require_parser_support!
      rescue DabUnsupportedSyntaxProfileError
        if empty_modern_application?(source_unit, source_units: source_units, ring_bases: ring_bases)
          next
        end

        raise_diagnostic(source_unit)
      end
    end

    source_units
  end

  def validate_source_content!(source_unit, content)
    return source_unit unless source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
    return source_unit if content.empty?

    raise_diagnostic(source_unit)
  end

  def empty_modern_application?(source_unit, source_units:, ring_bases:)
    return false unless source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
    return false unless source_units.one?
    return false if Array(ring_bases).empty?
    return false unless source_unit.input.is_a?(String)

    File.file?(source_unit.input) && File.zero?(source_unit.input)
  end

  def raise_diagnostic(source_unit)
    source_unit.require_parser_support!
  rescue DabUnsupportedSyntaxProfileError => e
    location = DabSourceLocation.new(
      source_unit: source_unit,
      offset: 0,
      line: 1,
      column: 0
    )
    raise DabModernSyntaxDiagnosticError.new(e.message, source_location: location)
  end
end

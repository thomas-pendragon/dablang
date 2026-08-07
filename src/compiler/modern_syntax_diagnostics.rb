require_relative '../shared/source_location'
require_relative 'modern_bootstrap_parser'

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
        if supported_modern_application?(source_unit, source_units: source_units, ring_bases: ring_bases)
          next
        end

        source_unit.require_parser_support!
      rescue DabUnsupportedSyntaxProfileError => e
        raise_diagnostic(source_unit, e)
      end
    end

    source_units
  end

  def validate_source_content!(source_unit, content)
    return source_unit unless source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
    return nil if content.empty?

    DabModernBootstrapParser.new(content, source_unit: source_unit).parse
  rescue DabUnsupportedSyntaxProfileError => e
    raise_diagnostic(source_unit, e)
  end

  def lower_document!(document, unit)
    document.lower_into(unit)
  rescue DabUnsupportedSyntaxProfileError => e
    raise_diagnostic(document.source_unit, e)
  end

  def supported_modern_application?(source_unit, source_units:, ring_bases:)
    return false unless modern_application_candidate?(
      source_unit,
      source_units: source_units,
      ring_bases: ring_bases
    )
    return true if File.zero?(source_unit.input)

    DabModernBootstrapParser.new(File.binread(source_unit.input), source_unit: source_unit).parse
    true
  rescue SystemCallError
    false
  end

  def modern_application_candidate?(source_unit, source_units:, ring_bases:)
    return false unless source_unit.syntax_profile.equal?(DabSyntaxProfile::MODERN)
    return false unless source_units.one?
    return false if Array(ring_bases).empty?
    return false unless source_unit.input.is_a?(String)

    File.file?(source_unit.input)
  end

  def raise_diagnostic(source_unit, error)
    location = if error.respond_to?(:source_location)
                 error.source_location
               else
                 DabSourceLocation.new(
                   source_unit: source_unit,
                   offset: 0,
                   line: 1,
                   column: 0
                 )
               end
    raise DabModernSyntaxDiagnosticError.new(error.message, source_location: location)
  end
end

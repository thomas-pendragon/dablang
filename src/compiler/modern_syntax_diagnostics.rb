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

  def validate_source_units!(source_units)
    source_units.each do |source_unit|
      begin
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

    source_units
  end
end

require_relative '../setup'
require_relative '../src/shared/system'

FILES = ['./src/compiler/_requires.rb'].freeze

check = ARGV.last == '--check'

FILES.each do |file|
  if check
    psystem("sort #{file} | diff #{file} -")
  else
    psystem("sort #{file} -o #{file}")
  end
end

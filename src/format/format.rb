if ARGV.include?('--version')
  require_relative '../shared/version'
  DabVersion.print_and_exit('formatter')
end

require_relative '../../setup'
require_relative '../compiler/_requires'

stream = DabProgramStream.new(STDIN.read)
compiler = DabCompiler.new(stream)
program = compiler.program

options = {}

program.dump
puts program.formatted_source(options)

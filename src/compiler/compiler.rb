require_relative '../shared/debug_output.rb'
require_relative 'nodes/node.rb'
require_relative 'nodes/node_arg.rb'
require_relative 'nodes/node_arg_definition.rb'
require_relative 'nodes/node_call.rb'
require_relative 'nodes/node_code_block.rb'
require_relative 'nodes/node_constant.rb'
require_relative 'nodes/node_constant_reference.rb'
require_relative 'nodes/node_define_local_var.rb'
require_relative 'nodes/node_function.rb'
require_relative 'nodes/node_if.rb'
require_relative 'nodes/node_list_node.rb'
require_relative 'nodes/node_literal.rb'
require_relative 'nodes/node_literal_boolean.rb'
require_relative 'nodes/node_literal_number.rb'
require_relative 'nodes/node_literal_string.rb'
require_relative 'nodes/node_local_var.rb'
require_relative 'nodes/node_operator.rb'
require_relative 'nodes/node_property_get.rb'
require_relative 'nodes/node_return.rb'
require_relative 'nodes/node_symbol.rb'
require_relative 'nodes/node_type.rb'
require_relative 'nodes/node_unit.rb'
require_relative 'parts/compiler.rb'
require_relative 'parts/context.rb'
require_relative 'parts/exceptions.rb'
require_relative 'parts/output.rb'
require_relative 'parts/program_stream.rb'
require_relative 'parts/types.rb'
require_relative 'postproc/check_call_args_types.rb'
require_relative 'postproc/check_functions.rb'
require_relative 'postproc/check_setvar_types.rb'
require_relative 'postproc/compact_constants.rb'
require_relative 'postproc/fix_literals.rb'
require_relative 'postproc/fix_localvars.rb'
require_relative 'postproc/reuse_constants.rb'
require_relative 'postproc/simplify_constant_properties.rb'
require_relative 'postproc/strip_single_vars.rb'

stream = DabProgramStream.new(STDIN.read)
compiler = DabCompiler.new(stream)
program = compiler.program

program.dump

postprocess = [
  DabPPFixLiterals,
  DabPPFixLocalvars,
  DabPPReuseConstants,
  DabPPCompactConstants,
  DabPPCheckFunctions,
  DabPPCheckSetvarTypes,
  DabPPCheckCallArgsTypes,
  DabPPStripSingleVars,
  DabPPSimplifyConstantProperties,
]

2.times do
  postprocess.each do |klass|
    STDERR.puts "Will run postprocess <#{klass}>"
    klass.new.run(program)
    program.dump
  end
  break if program.has_errors?
end

STDERR.puts "\n--\n\n"

program.dump

if program.has_errors?
  program.errors.each do |e|
    STDERR.puts sprintf('%s:%d: error E%04d: %s', e.source.source_file, e.source.source_line, e.error_code, e.message)
  end
  exit(1)
else
  output = DabOutput.new
  program.compile(output)
end

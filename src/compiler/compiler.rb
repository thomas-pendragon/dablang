require_relative '../shared/debug_output.rb'
require_relative 'nodes/node.rb'
require_relative 'nodes/node_arg.rb'
require_relative 'nodes/node_call.rb'
require_relative 'nodes/node_code_block.rb'
require_relative 'nodes/node_constant.rb'
require_relative 'nodes/node_constant_reference.rb'
require_relative 'nodes/node_define_local_var.rb'
require_relative 'nodes/node_function.rb'
require_relative 'nodes/node_literal.rb'
require_relative 'nodes/node_literal_number.rb'
require_relative 'nodes/node_literal_string.rb'
require_relative 'nodes/node_local_var.rb'
require_relative 'nodes/node_operator.rb'
require_relative 'nodes/node_symbol.rb'
require_relative 'parts/compiler.rb'
require_relative 'parts/context.rb'
require_relative 'parts/output.rb'
require_relative 'parts/program_stream.rb'
require_relative 'postproc/fix_literals.rb'
require_relative 'postproc/fix_localvars.rb'

stream = DabProgramStream.new(STDIN.read)
compiler = DabCompiler.new(stream)
program = compiler.program

program.dump

DabPPFixLiterals.new.run(program)
DabPPFixLocalvars.new.run(program)

program.dump

output = DabOutput.new
program.compile(output)

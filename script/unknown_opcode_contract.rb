#!/usr/bin/env ruby

require_relative '../lib/dab/unknown_opcode_contract'

root = File.expand_path('..', __dir__)
exit Dab::UnknownOpcodeContract::Runner.new(root: root).run

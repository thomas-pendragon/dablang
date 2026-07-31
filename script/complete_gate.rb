#!/usr/bin/env ruby

require_relative '../lib/dab/complete_gate'

root = File.expand_path('..', __dir__)
exit Dab::CompleteGate::Runner.new(root: root).run

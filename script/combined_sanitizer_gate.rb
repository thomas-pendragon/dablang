#!/usr/bin/env ruby

require_relative '../lib/dab/combined_sanitizer_gate'

root = File.expand_path('..', __dir__)
exit Dab::CombinedSanitizerGate::Runner.new(root: root).run

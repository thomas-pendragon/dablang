#!/usr/bin/env ruby

require_relative '../lib/dab/undefined_behavior_sanitizer_gate'

root = File.expand_path('..', __dir__)
exit Dab::UndefinedBehaviorSanitizerGate::Runner.new(root: root).run

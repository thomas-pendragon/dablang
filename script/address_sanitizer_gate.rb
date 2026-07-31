#!/usr/bin/env ruby

require_relative '../lib/dab/address_sanitizer_gate'

root = File.expand_path('..', __dir__)
exit Dab::AddressSanitizerGate::Runner.new(root: root).run

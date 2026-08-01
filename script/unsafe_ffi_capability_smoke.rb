#!/usr/bin/env ruby

require_relative '../lib/dab/unsafe_ffi_capability_smoke'

root = File.expand_path('..', __dir__)
exit Dab::UnsafeFfiCapabilitySmoke::Runner.new(root: root).run

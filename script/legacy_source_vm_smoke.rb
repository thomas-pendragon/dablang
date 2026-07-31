#!/usr/bin/env ruby

require_relative '../lib/dab/legacy_source_vm_smoke'

root = File.expand_path('..', __dir__)
exit Dab::LegacySourceVmSmoke::Runner.new(root: root).run

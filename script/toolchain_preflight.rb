#!/usr/bin/env ruby

require_relative '../lib/dab/toolchain_preflight'

root = File.expand_path('..', __dir__)
result = Dab::ToolchainPreflight::Runner.new(root: root).run
stream = result.success ? $stdout : $stderr
stream.write(result.output)
exit(result.success ? 0 : 1)

#!/usr/bin/env ruby

require_relative '../lib/dab/test_suite_manifest'

root = File.expand_path('..', __dir__)
path = ARGV.fetch(0, File.join(root, 'config/test_suites.json'))
result = Dab::TestSuiteManifest::Validator.new(root: root).validate(path: path)

if result.success?
  puts "test suite manifest: OK (#{result.suite_count} suites, #{result.exception_count} exceptions)"
  exit 0
end

warn 'test suite manifest: FAILED'
result.errors.each { |error| warn "  #{error}" }
exit 1

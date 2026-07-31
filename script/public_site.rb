#!/usr/bin/env ruby

require_relative '../lib/dab/public_site'

root = File.expand_path('..', __dir__)
exit Dab::PublicSite::Runner.new(root: root).run

require_relative './shared_noautorun.rb'

read_args!
raise 'no input' unless $settings[:input]

include BaseFrontend

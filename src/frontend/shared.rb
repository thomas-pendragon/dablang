require_relative 'shared_noautorun'

read_args!
raise 'no input' unless $settings[:input]

include BaseFrontend

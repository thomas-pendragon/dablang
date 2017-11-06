require_relative './common_tools.rb'
require_relative '../src/shared/opcodes.rb'

source = 'src/shared/opcodes.rb'

puts "---
layout: page
title: VM opcodes
exclude_from_nav: true
---

"

index = 0

OPCODES_ARRAY_BASE.each do |group|
  title = group[:group]
  items = group[:items]

  next if items.empty?

  puts "## #{title}

|Opcode |Name    |Arguments|
|-------|--------|---------|
"

  items.each do |item|
    args = (item[:args] || []).map { |arg| "`#{arg}`" }.join(', ')
    format = '|`%02X`|`%s`|%s|'
    puts sprintf(format, index, item[:name], args)
    index += 1
  end

  puts "
<br>
"
end

puts "Autogenerated from `#{source}`, last revised: #{file_date(source)}"

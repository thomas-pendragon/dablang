require_relative './common_tools.rb'
require_relative '../src/shared/opcodes.rb'

source = 'src/shared/opcodes.rb'
date_source = 'src/cshared/classes.h'

classes_data = ''

classes_data << "---
  layout: page
  title: Classes
---

"

STANDARD_CLASSES.each_with_index do |klass, index|
  klass_file = klass.downcase

  data = ''

  data << "---
  layout: page
  title: #{klass}
  exclude_from_nav: true
---

  "

  data << "VM index: `#{index}`\n\n"

  data << "Autogenerated from `#{source}`, last revised: #{git_date(date_source)}"

  classes_data << "- [#{klass}](/classes/#{klass_file}.html)\n"

  File.open("./docs/classes/#{klass_file}.md", 'wb') { |file| file << data }
end

File.open('./docs/classes.md', 'wb') { |file| file << classes_data }

Pry.config.editor = proc { |file, line| "subl #{file}:#{line}" }
Pry.config.commands.alias_command 'bt', 'backtrace'

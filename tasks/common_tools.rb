require 'date'

def git_date(file)
  return nil unless File.exist?(file)
  value = `git log -1 --format=%cd #{file}`
  value = DateTime.parse(value)
  value.strftime('%Y-%m-%d')
end

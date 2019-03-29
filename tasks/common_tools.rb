require 'date'

def format_date(date)
  date.strftime('%Y-%m-%d')
end

def git_date(file)
  return nil unless File.exist?(file)

  value = `git log -1 --format=%cd #{file}`
  value = DateTime.parse(value)
  format_date(value)
end

def file_date(file)
  value = File.mtime(file)
  format_date(value)
end

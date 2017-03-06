require 'yaml'

base_path = 'gitlab_base.yml'

data = YAML.load_file(base_path)

compilers = [
  'g++-4.7',
  'g++-4.8',
  'g++-4.9',
  'g++-5',
  'g++-6',
  'clang++-3.5',
  'clang++-3.6',
  'clang++-3.7',
  'clang++-3.8',
  'clang++-3.9',
]

compilers = compilers.map do |compiler|
  env = "env_#{compiler.gsub(/[^a-z0-9]+/, '_')}"
  [compiler, env]
end.to_h

compilers.each do |compiler, env|
  data[".#{env}"] = {
    'variables' => {
      'CXX' => compiler,
    },
  }
end

compilers.each do |compiler, env|
  %w(Build Test).each do |stage|
    task_name = "#{stage} #{compiler}"
    task = {}
    task.merge! data[".#{stage.downcase}_base"]
    task.merge! data[".#{env}"]
    if stage == 'Test'
      task['dependencies'] = ["Build #{compiler}"]
    end
    data[task_name] = task
  end
end

puts YAML.dump(data)

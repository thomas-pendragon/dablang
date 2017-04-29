require 'yaml'

base_path = 'gitlab_base.yml'

data = YAML.load_file(base_path)

compilers = [
  'g++-4.7',
  # 'g++-4.8',
  # 'g++-4.9',
  # 'g++-5',
  # 'g++-6',
  'clang++-3.5',
  # 'clang++-3.6',
  # 'clang++-3.7',
  # 'clang++-3.8',
  # 'clang++-3.9',
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

stage_jobs = {
  'Build' => [''],
  'Test' => %w(spec vm_spec format_spec disasm_spec asm_spec dumpcov_spec cov_spec debug_spec),
}

compilers.each do |compiler, env|
  %w(Build Test).each do |stage|
    stage_jobs[stage].each do |job|
      lookup = ".#{stage.downcase}_base_#{job}".gsub(/_$/, '')
      task_name = "#{stage} #{compiler} #{job}".strip
      task = {}
      task.merge! data[lookup]
      task.merge! data[".#{env}"]
      if stage == 'Test'
        task['dependencies'] = ["Build #{compiler}"]
      end
      data[task_name] = task
    end
  end
end

puts YAML.dump(data)

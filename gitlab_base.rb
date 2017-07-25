require_relative 'setup.rb'

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
  'Test' => %w(spec vm_spec disasm_spec dumpcov_spec cov_spec debug_spec),
}

split = {
  'spec' => 10,
  'asm_spec' => 2,
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
      task_split = split[job] || 1
      if task_split > 1
        task_split.times do |index|
          sub_task = task.dup
          sub_task['variables'] = (sub_task['variables'] || {}).dup
          sub_task['variables']['CI_PARALLEL_INDEX'] = index.to_s
          sub_task['variables']['CI_PARALLEL_TOTAL'] = task_split.to_s
          data[task_name + " #{index} #{task_split}"] = sub_task
        end
      else
        data[task_name] = task
      end
    end
  end
end

puts YAML.dump(data)

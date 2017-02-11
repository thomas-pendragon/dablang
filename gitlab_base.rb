puts <<-EOT
image: dablang/dablangenv:0.1

before_script:
  - gem install bundler
  - bundle install --path=/cache/bundler

stages:
  - build
  - test

.build_base: &build_base
  stage: build
  tags:
    - ruby
  script:
    - bundle exec rake bin/cvm

.test_base: &test_base
  stage: test
  tags:
    - ruby
  script:
    - bundle exec rake spec
EOT

puts

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
  puts ".#{env}: &#{env}"
  puts '  variables:'
  puts "    COMPILER: #{compiler}"
  puts
end

compilers.each do |compiler, env|
  puts "'Build #{compiler}':"
  puts '  <<: *build_base'
  puts "  <<: *#{env}"
  puts
  puts "'Test #{compiler}':"
  puts '  <<: *test_base'
  puts "  <<: *#{env}"
  puts
end

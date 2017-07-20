$dab_benchmark_stack = []
$dab_benchmark_data = {}

def dab_benchmark(name)
  return yield unless $dab_benchmark_enabled

  data = $dab_benchmark_data

  $dab_benchmark_stack.each do |parent|
    data = data[parent][:children]
  end

  unless data[name]
    data[name] = {
      name: name,
      time: 0.0,
      children: {},
    }
  end

  data = data[name]

  $dab_benchmark_stack << name

  start = Time.now
  ret = yield
  finish = Time.now

  data[:time] += finish - start

  $dab_benchmark_stack.pop

  ret
end

def _dab_benchmark_print(file, level, list, subtotal, total)
  list = list.values.sort_by { |item| -item[:time] }
  list.each do |item|
    len = 120 - level * 2
    file.printf("%s%-#{len}s | %8.4fs |  %6.2f%% | %6.2f%%\n", ' ' * (level * 2), item[:name], item[:time], 100.0 * item[:time] / subtotal, 100.0 * item[:time] / total)
    sublist = item[:children]
    _dab_benchmark_print(file, level + 1, sublist, item[:time], total)
  end
end

def dab_benchmark_print!
  return unless $dab_benchmark_enabled

  file = STDERR
  file.printf("%-120s |   Time    | Relative |  Total\n", 'Name')
  file.printf("%s-+-----------+----------+---------\n", '-' * 120)
  total = $dab_benchmark_data.map { |_, node| node[:time] }.reduce(&:+)
  _dab_benchmark_print(file, 0, $dab_benchmark_data, total, total)
end

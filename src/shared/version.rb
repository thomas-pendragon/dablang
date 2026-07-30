module DabVersion
  VERSION_FILE = File.expand_path('../../VERSION', __dir__)

  def self.print_and_exit(tool)
    puts "Dab #{tool} #{File.read(VERSION_FILE).strip}"
    exit 0
  end
end

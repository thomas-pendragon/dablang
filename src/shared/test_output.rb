require 'monitor'

module DabTestOutput
  OUTPUT_MONITOR = Monitor.new

  class SessionIO
    def initialize(session, stream)
      @session = session
      @stream = stream
    end

    def write(value)
      text = value.to_s
      @session.capture(text, stream: @stream, display: @stream)
      text.bytesize
    end

    alias << write

    def print(*values)
      values.each { |value| write(value) }
      nil
    end

    def puts(*values)
      values = [''] if values.empty?
      values.each do |value|
        write(value)
        write("\n") unless value.to_s.end_with?("\n")
      end
      nil
    end

    def flush
      self
    end

    def sync
      true
    end

    def sync=(value)
      value
    end

    def tty?
      false
    end
  end

  class Session
    attr_reader :identity

    def initialize(identity, output:, error:, verbose: ENV['DAB_TEST_VERBOSE'] == '1')
      @identity = identity.to_s
      @output = output
      @error = error
      @verbose = verbose
      @events = []
      @actions = []
      @commands = []
      @current_action = nil
    end

    def capture(text, stream:, display: stream)
      @events << [stream, display, text]
      return unless @verbose

      destination(display).write(text)
    end

    def status(text)
      @output.write("#{text}\n")
    end

    def start_action(stage, command: nil)
      @current_action = stage.to_s
      @actions << {stage: @current_action, command: command}
    end

    def finish_action
      @current_action = nil
    end

    def record_command(command, exit_code:, stdout:, stderr:)
      @commands << {
        stage: @current_action || 'unknown',
        command: command.to_s,
        exit_code: normalize_exit_code(exit_code),
        stdout: stdout.to_s,
        stderr: stderr.to_s,
      }
    end

    def pass
      status("PASS #{@identity}")
    end

    def failure(exception)
      @error.write("\nDab test failure: #{@identity}\n")
      @error.write("exception: #{exception.class}: #{exception.message}\n")
      report_commands
      @error.write("captured per-test output:\n")
      @events.each do |_stream, display, text|
        destination(display).write(text)
      end
    end

  private

    def destination(stream)
      stream == :stderr ? @error : @output
    end

    def normalize_exit_code(status)
      return status if status.is_a?(Integer)

      if status.respond_to?(:exitstatus)
        return status.exitstatus if status.exitstatus
        return 128 + status.termsig if status.respond_to?(:signaled?) && status.signaled?

        return 1
      end

      status.to_i
    end

    def report_commands
      reported = false
      @commands.each do |command|
        reported = true
        @error.write("stage: #{command[:stage]}\n")
        @error.write("command: #{command[:command]}\n")
        @error.write("exit status: #{command[:exit_code]}\n")
        @error.write("stdout:\n#{command[:stdout]}") unless command[:stdout].empty? || captured?(:stdout, command[:stdout])
        @error.write("stderr:\n#{command[:stderr]}") unless command[:stderr].empty? || captured?(:stderr, command[:stderr])
        @error.write("\n")
      end
      return if reported

      @actions.each do |action|
        next unless action[:command]

        @error.write("stage: #{action[:stage]}\n")
        @error.write("command: #{action[:command]}\n")
        @error.write("exit status: unavailable (no subprocess)\n")
      end
    end

    def captured?(stream, text)
      captured = @events.filter_map { |event_stream, _display, event_text| event_text if event_stream == stream }.join
      captured.include?(text)
    end
  end

  class << self
    def current
      Thread.current[:dab_test_output_session]
    end

    def emit(text, stream: :stderr, display: stream)
      if current
        current.capture(text, stream: stream, display: display)
      else
        destination = display == :stderr ? STDERR : STDOUT
        destination.write(text)
      end
    end

    def with_action(stage, command: nil)
      session = current
      return yield unless session

      session.start_action(stage, command: command)
      yield
    ensure
      session&.finish_action
    end

    def record_command(command, exit_code:, stdout:, stderr:)
      current&.record_command(command, exit_code: exit_code, stdout: stdout, stderr: stderr)
    end

    def with_test(identity, output: $stdout, error: $stderr)
      session = Session.new(identity, output: output, error: error)
      OUTPUT_MONITOR.synchronize do
        previous = current
        Thread.current[:dab_test_output_session] = session
        previous_stdout = $stdout
        previous_stderr = $stderr
        $stdout = SessionIO.new(session, :stdout)
        $stderr = SessionIO.new(session, :stderr)

        begin
          yield
          session.pass
        rescue StandardError => e
          session.failure(e)
          raise
        ensure
          $stdout = previous_stdout
          $stderr = previous_stderr
          Thread.current[:dab_test_output_session] = previous
        end
      end
    end

    def summary(name, count, output: $stdout)
      output.puts("#{name}: #{count} test(s) completed")
    end

    def printf(format_string, *arguments)
      emit(sprintf(format_string, *arguments))
    end
  end
end

require 'spec_helper'

require 'stringio'

require_relative '../src/shared/test_output'

describe DabTestOutput do
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }

  around do |example|
    begin
      verbose = ENV.delete('DAB_TEST_VERBOSE')
      example.run
    ensure
      ENV['DAB_TEST_VERBOSE'] = verbose if verbose
    end
  end

  it 'keeps successful test output concise and emits a pass status' do
    DabTestOutput.with_test('test/dab/0001_simple.dabt', output: output, error: error) do
      warn 'compiler command details'
      puts 'VM output details'
    end

    expect(output.string).to eq("PASS test/dab/0001_simple.dabt\n")
    expect(error.string).to eq('')
  end

  it 'replays failure output with identity, stage, command, status, and diagnostics' do
    expect do
      DabTestOutput.with_test('test/vm/0001_failure.vmt', output: output, error: error) do
        DabTestOutput.with_action('VM') do
          DabTestOutput.record_command(
            './bin/cvm --test',
            exit_code: 17,
            stdout: "partial stdout\n",
            stderr: "runtime diagnostic\n"
          )
          raise 'fixture failed'
        end
      end
    end.to raise_error('fixture failed')

    expect(error.string).to include(
      'Dab test failure: test/vm/0001_failure.vmt',
      'stage: VM',
      'command: ./bin/cvm --test',
      'exit status: 17',
      'runtime diagnostic'
    )
  end

  it 'forwards detailed successful output when verbose mode is enabled' do
    ENV['DAB_TEST_VERBOSE'] = '1'

    DabTestOutput.with_test('test/asm/0001_simple.asmt', output: output, error: error) do
      warn 'assembler command details'
      puts 'assembler output details'
    end

    expect(output.string).to include('assembler output details', 'PASS test/asm/0001_simple.asmt')
    expect(error.string).to include('assembler command details')
  end

  it 'reports concise suite summaries' do
    DabTestOutput.summary('vm_spec', 12, output: output)

    expect(output.string).to eq("vm_spec: 12 test(s) completed\n")
  end
end

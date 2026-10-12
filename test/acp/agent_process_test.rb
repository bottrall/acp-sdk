# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'stringio'
require 'timeout'
require 'tmpdir'

class AgentProcessFakeWaiter
  attr_reader :pid

  def initialize(pid, joins = [])
    @pid = pid
    @joins = joins
  end

  def join(_timeout)
    @joins.empty? || @joins.shift
  end
end

class AgentProcessFakeReader
  attr_reader :timeouts

  def initialize
    @timeouts = []
  end

  def join(timeout)
    @timeouts << timeout
    self
  end
end

describe ACP::AgentProcess do
  def within(seconds = 5, &)
    Timeout.timeout(seconds, &)
  end

  def unreached
    ->(_request) { raise 'not reached' }
  end

  def spawn_ruby(script, *, **, &)
    ACP::AgentProcess.spawn(RbConfig.ruby, '-e', script, *, permission: unreached, **, &)
  end

  def captured(script, *, **)
    process = spawn_ruby(script, *, stderr: :capture, **)
    process.terminate
    process.stderr
  end

  def child(setup = '', body = 'sleep', **)
    ready, out = IO.pipe
    pid = Process.spawn(RbConfig.ruby, '-e', "#{setup}; puts :ready; STDOUT.flush; #{body}", out:, **)
    out.close
    within { ready.gets }
    ready.close
    pid
  end

  def reap(pid)
    within { Process.wait2(pid).last }
  rescue Timeout::Error
    Process.kill('KILL', pid)
    Process.wait(pid)
    raise
  end

  def exited_pid
    pid = Process.spawn(RbConfig.ruby, '-e', '')
    reap(pid)
    pid
  end

  def build(waiter, stdin: StringIO.new, stdout: StringIO.new, reader: Thread.new { nil }, err_r: nil)
    ACP::AgentProcess.new(connection: Object.new, reader:, stdin:, stdout:, waiter:, err_r:)
  end

  describe '.spawn' do
    it 'collects the child stderr when given stderr: :capture' do
      assert_equal "boom\n", captured('STDERR.puts(:boom)')
    end

    it 'leaves stderr uncollected by default' do
      process = spawn_ruby('STDIN.read')
      process.terminate

      assert_nil process.stderr
    end

    it 'runs the command with its args in the directory of the caller' do
      assert_equal "#{Dir.pwd}:a:b\n", captured('STDERR.puts([Dir.pwd, *ARGV].join(":"))', 'a', 'b')
    end

    it 'runs the command in cwd' do
      cwd = File.realpath(Dir.tmpdir)

      assert_equal "#{cwd}\n", captured('STDERR.puts(Dir.pwd)', cwd:)
    end

    it 'adds env to the environment of the command' do
      env = { 'ACP_AGENT_PROCESS_TEST' => 'x' }

      assert_equal "x:a\n", captured('STDERR.puts([ENV["ACP_AGENT_PROCESS_TEST"], *ARGV].join(":"))', 'a', env:)
    end

    it 'returns the running process when given no block' do
      process = spawn_ruby('STDIN.read')
      begin
        assert_equal [ACP::AgentProcess, 1], [process.class, Process.kill(0, process.pid)]
      ensure
        process.terminate
      end
    end

    it 'yields the connection and the process, returns the block value and terminates the child' do
      yielded = nil
      result = spawn_ruby('STDIN.read') do |connection, process|
        yielded = [connection.equal?(process.connection), Process.kill(0, process.pid), process.pid]
        :result
      end

      assert_equal [:result, true, 1], [result, *yielded.first(2)]
      assert_raises(Errno::ESRCH) { Process.kill(0, yielded.last) }
    end

    it 'terminates the child when the block raises' do
      pid = nil
      error = assert_raises(RuntimeError) do
        spawn_ruby('STDIN.read') do |_connection, process|
          pid = process.pid
          raise 'boom'
        end
      end

      assert_equal 'boom', error.message
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    end
  end

  describe '#terminate' do
    it 'closes the stdin of the child' do
      stdin = StringIO.new
      build(AgentProcessFakeWaiter.new(exited_pid), stdin:).terminate

      assert_predicate stdin, :closed?
    end

    it 'sends no signal to a child that exits once its stdin closes' do
      in_r, in_w = IO.pipe
      pid = child('', 'STDIN.read', in: in_r)
      in_r.close
      build(AgentProcessFakeWaiter.new(pid)).terminate
      in_w.close

      assert_predicate reap(pid), :success?
    end

    it 'sends TERM to a child that outlives its stdin' do
      pid = child
      build(AgentProcessFakeWaiter.new(pid, [nil])).terminate

      assert_equal Signal.list.fetch('TERM'), reap(pid).termsig
    end

    it 'sends KILL to a child that outlives TERM' do
      pid = child('trap("TERM", "IGNORE")')
      build(AgentProcessFakeWaiter.new(pid, [nil, nil])).terminate

      assert_equal Signal.list.fetch('KILL'), reap(pid).termsig
    end

    it 'waits for the reader thread' do
      reader = AgentProcessFakeReader.new
      build(AgentProcessFakeWaiter.new(exited_pid), reader:).terminate

      assert_equal [1], reader.timeouts
    end

    it 'closes the stdout of the child' do
      stdout = StringIO.new
      build(AgentProcessFakeWaiter.new(exited_pid), stdout:).terminate

      assert_predicate stdout, :closed?
    end

    it 'waits for the stderr reader' do
      err_r, err_w = IO.pipe
      process = build(AgentProcessFakeWaiter.new(exited_pid), err_r:)
      Thread.new do
        sleep 0.05
        err_w.write("late\n")
        err_w.close
      end
      process.terminate

      assert_equal "late\n", process.stderr
    end

    it 'closes the stderr pipe' do
      err_r, err_w = IO.pipe
      process = build(AgentProcessFakeWaiter.new(exited_pid), err_r:)
      err_w.close
      process.terminate

      assert_predicate err_r, :closed?
    end
  end

  describe '#stderr' do
    it 'is every line read from the stderr pipe' do
      err_r, err_w = IO.pipe
      process = build(AgentProcessFakeWaiter.new(exited_pid), err_r:)
      err_w.write("one\ntwo\n")
      err_w.close
      process.terminate

      assert_equal "one\ntwo\n", process.stderr
    end

    it 'is nil without a stderr pipe' do
      process = build(AgentProcessFakeWaiter.new(exited_pid))
      process.terminate

      assert_nil process.stderr
    end
  end

  describe 'signalling' do
    it 'ignores a child that is already gone' do
      stdout = StringIO.new
      build(AgentProcessFakeWaiter.new(exited_pid, [nil, nil]), stdout:).terminate

      assert_predicate stdout, :closed?
    end
  end
end

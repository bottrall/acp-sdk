# frozen_string_literal: true

require 'open3'

class ACP::AgentProcess
  # @rbs @connection: ACP::ClientConnection
  # @rbs @reader: Thread
  # @rbs @pid: Integer
  # @rbs @stdin: IO
  # @rbs @stdout: IO
  # @rbs @waiter: Process::Waiter
  # @rbs @err_r: IO?
  # @rbs @err_reader: Thread?
  # @rbs @stderr: String?

  # @dynamic pid
  attr_reader :pid #: Integer

  # @dynamic connection
  attr_reader :connection #: ACP::ClientConnection

  # @dynamic stderr
  attr_reader :stderr #: String?

  # @rbs command: String
  # @rbs *args: String
  # @rbs env: Hash[String, String]?
  # @rbs cwd: String?
  # @rbs stderr: (:inherit | :capture)
  # @rbs permission: ACP::ClientConnection::_PermissionHandler
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs &block: ? (ACP::ClientConnection, ACP::AgentProcess) -> untyped
  # @rbs return: (untyped | ACP::AgentProcess)
  def self.spawn(
    command,
    *args,
    permission:,
    env: nil,
    cwd: nil,
    stderr: :inherit,
    updates: ACP::ClientConnection::IGNORE,
    &block
  )
    err_r, err_w = stderr == :capture ? IO.pipe : nil
    opts = {} #: Hash[Symbol, untyped]
    opts[:chdir] = cwd if cwd
    opts[:err] = err_w if err_w
    spawner = Open3.method(:popen2) #: _Spawner
    stdin, stdout, waiter = spawner.call(*(env ? [env, command, *args] : [command, *args]), **opts)
    err_w&.close
    connection = ACP::ClientConnection.build(
      transport: ACP::Transport::Stdio.new(input: stdout, output: stdin),
      permission:,
      updates:
    )
    process = new(connection:, reader: connection.start, stdin:, stdout:, waiter:, err_r:)
    return process unless block

    begin
      yield connection, process
    ensure
      process.terminate
    end
  end

  # @rbs return: void
  def terminate
    @stdin.close
    @waiter.join(1) or signal('TERM')
    @waiter.join(2) or signal('KILL')
    @waiter.join(2)
    @reader.join(1)
    @stdout.close
    @err_reader&.join(1)
    @err_r&.close
  end

  private

  # @rbs connection: ACP::ClientConnection
  # @rbs reader: Thread
  # @rbs stdin: IO
  # @rbs stdout: IO
  # @rbs waiter: Process::Waiter
  # @rbs err_r: IO?
  # @rbs return: void
  def initialize(connection:, reader:, stdin:, stdout:, waiter:, err_r:)
    @connection = connection
    @reader = reader
    @pid = waiter.pid
    @stdin = stdin
    @stdout = stdout
    @waiter = waiter
    @err_r = err_r
    @stderr = err_r ? +'' : nil
    @err_reader = Thread.new { err_r.each_line { |line| @stderr&.concat(line) } } if err_r
  end

  # @rbs sig: String
  # @rbs return: void
  def signal(sig)
    Process.kill(sig, @pid)
  rescue Errno::ESRCH
    nil
  end
end

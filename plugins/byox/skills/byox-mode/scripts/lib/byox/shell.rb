# frozen_string_literal: true

module Byox
  module Shell
    module_function

    # Runs cmd (a shell string or an argv array) in cwd with stdout and stderr merged.
    # Yields each line as it arrives and returns the exit code. A timeout kills the
    # whole process group and returns 124, like timeout(1).
    def stream(cmd, cwd:, env: {}, timeout: 600)
      argv = cmd.is_a?(Array) ? cmd : ["sh", "-c", cmd]
      Open3.popen2e(env, *argv, chdir: cwd, pgroup: true) do |stdin, out, wait|
        stdin.close
        timer = Thread.new do
          sleep timeout
          Process.kill("KILL", -wait.pid)
        rescue Errno::ESRCH
          nil
        end
        out.each_line { |line| yield line if block_given? }
        status = wait.value
        timer.kill
        status.exitstatus || 124
      end
    end

    def capture(cmd, cwd:, env: {}, timeout: 600)
      buf = +""
      code = stream(cmd, cwd:, env:, timeout:) { buf << _1 }
      [code, buf]
    end
  end
end

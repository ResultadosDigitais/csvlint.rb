require "aruba"
require "aruba/cucumber"
require "stringio"

require "csvlint/cli"

module Csvlint
  # Stands in for an empty stdin. The CLI treats a nil read as "no CSV data to
  # validate", which an empty StringIO (whose read returns "") would not.
  class EmptyStdin < StringIO
    def read(*)
      nil
    end
  end

  class CliRunner
    # Aruba's in-process launcher passes its own StringIO as stdin, so stubbing
    # $stdin from a step never reaches the command. Steps set this instead.
    class << self
      attr_accessor :stdin_override
    end

    # Allow everything fun to be injected from the outside while defaulting to normal implementations.
    def initialize(argv, stdin = $stdin, stdout = $stdout, stderr = $stderr, kernel = Kernel)
      @argv, @stdin, @stdout, @stderr, @kernel = argv, stdin, stdout, stderr, kernel
    end

    def execute!
      exit_code = begin
        # Thor accesses these streams directly rather than letting them be injected, so we replace them...
        $stderr = @stderr
        $stdin = self.class.stdin_override || @stdin
        $stdout = @stdout

        # Run our normal Thor app the way we know and love.
        Csvlint::Cli.start(@argv.dup.unshift("validate"))

        # Thor::Base#start does not have a return value, assume success if no exception is raised.
        0
      rescue => e
        # The ruby interpreter would pipe this to STDERR and exit 1 in the case of an unhandled exception
        b = e.backtrace
        @stderr.puts("#{b.shift}: #{e.message} (#{e.class})")
        @stderr.puts(b.map { |s| "\tfrom #{s}" }.join("\n"))
        1
      rescue SystemExit => e
        e.status
      ensure
        # TODO: reset your app here, free up resources, etc.
        # Examples:
        # MyApp.logger.flush
        # MyApp.logger.close
        # MyApp.logger = nil
        #
        # MyApp.reset_singleton_instance_variables

        # ...then we put the streams back.
        $stderr = STDERR
        $stdin = STDIN
        $stdout = STDOUT
        self.class.stdin_override = nil
      end

      # Proxy our exit code back to the injected kernel.
      @kernel.exit(exit_code)
    end
  end
end

Aruba.configure do |config|
  config.command_launcher = :in_process
  config.main_class = Csvlint::CliRunner
end

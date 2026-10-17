# frozen_string_literal: true

module Stockbar
  class Runner
    def run(*command)
      system(*command, out: File::NULL, err: File::NULL) == true
    end

    def capture(*command, check: true)
      output = IO.popen(command, err: File::NULL, &:read)
      !check || $?.success? ? output : nil
    rescue SystemCallError
      nil
    end
  end
end

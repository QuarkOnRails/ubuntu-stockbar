# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Stockbar
  module AtomicFile
    module_function

    # rename into place so the extension and the daemon never read a half-written file
    def write(path, content, mode: 0o644)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(content) }
      # open's mode goes through the umask
      File.chmod(mode, tmp)
      File.rename(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if tmp
    end
  end
end

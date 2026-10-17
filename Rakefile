# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

desc "Build the GNOME extension for GNOME_MAJOR into build/ (debian/rules passes the build system's version)"
task :extension do
  require_relative "lib/stockbar"
  require_relative "lib/stockbar/extension"

  major = Integer(ENV.fetch("GNOME_MAJOR", ""), exception: false) or abort "usage: rake extension GNOME_MAJOR=46"
  dir = File.join("build", "gnome-shell", "extensions", Stockbar::UUID)
  rm_rf dir
  variant = Stockbar::Extension.build(dir, major: major)
  puts "GNOME #{major} extension (#{variant}) → #{dir}"
end

task default: :test

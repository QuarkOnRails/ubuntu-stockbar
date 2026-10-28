# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = true
end

desc "Test pixel fitting without GNOME (requires node, no npm dependencies)"
task :test_layout do
  sh "node", "test/layout_test.js"
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

PPA = "ppa:quarkonrails/stockbar"
# launchpad builds each upload on its own release, so each gets the extension for that releases gnome.
# it rejects uploads for releases past their end of life, so interim releases leave this after 9 months
PPA_SERIES = { "jammy" => "22.04", "noble" => "24.04", "resolute" => "26.04", "stonking" => "26.10" }.freeze

desc "Signed source packages of HEAD into build/ppa/ for #{PPA}, PPA_BUILD=2 rebuilds the same version, " \
     "SERIES=stonking only builds that release"
task :ppa do
  require "tmpdir"

  abort "commit first, the packages are built from HEAD" unless `git status --porcelain --untracked-files=no`.empty?
  # a release that comes out mid-version goes up on its own, the others already have this version
  only = ENV.fetch("SERIES", PPA_SERIES.keys.join(",")).split(",")
  unknown = only - PPA_SERIES.keys
  abort "unknown SERIES #{unknown.join(",")}, the PPA has #{PPA_SERIES.keys.join(",")}" unless unknown.empty?
  base = `dpkg-parsechangelog -S Version`.strip
  build = ENV.fetch("PPA_BUILD", "1")
  out = File.expand_path("build/ppa")
  mkdir_p out

  uploads = PPA_SERIES.slice(*only).map do |series, release|
    # ~ sorts below the plain version, the release number makes an ubuntu upgrade pick the newer release's build
    version = "#{base}~#{release}.#{build}"
    Dir.mktmpdir do |tmp|
      source = File.join(tmp, "stockbar")
      sh "git archive --prefix=stockbar/ HEAD | tar -x -C #{tmp}"
      changelog = File.join(source, "debian", "changelog")
      File.write(changelog, File.read(changelog).sub(/\A.*/, "stockbar (#{version}) #{series}; urgency=medium"))
      Dir.chdir(source) { sh "debuild", "-S" }
      mv Dir[File.join(tmp, "stockbar_#{version}*")], out
    end
    File.join(out, "stockbar_#{version}_source.changes")
  end
  puts "", "upload with:", *uploads.map { |changes| "  dput #{PPA} #{changes}" }
end

task default: :test

#!/bin/sh
# installed as /usr/bin/stockbar. stockbar runs on the system ruby with the gems it ships, and settings
# from rvm, rbenv or bundler (another ruby's gem paths) would make that ruby load gems it can't run
unset GEM_HOME GEM_PATH GEM_ROOT RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_PATH
exec /usr/bin/ruby /usr/share/stockbar/bin/stockbar "$@"

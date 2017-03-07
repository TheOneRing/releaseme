formatters = []

begin
  require 'codeclimate-test-reporter'
  formatters << CodeClimate::TestReporter::Formatter
rescue LoadError
  warn 'codeclimate reporter not available, not sending reports to server'
end

begin
  require 'coveralls'
  formatters << Coveralls::SimpleCov::Formatter
rescue LoadError
  warn 'coveralls reporter not available, not sending reports to server'
end

begin
  require 'pullreview/coverage_reporter'
  formatters << PullReview::Coverage::Formatter
rescue LoadError => e
  warn 'pullreview reporter not available, not sending reports to server'
end

# HTML formatter.
formatters << SimpleCov::Formatter::HTMLFormatter

require 'simplecov'
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter[*formatters]
  add_filter do |src|
    # Special compat file for testing the compat code itself.
    next false if File.basename(src.filename) == 'compat_compat.rb'
    next false if File.basename(src.filename) == 'releaseme.rb'
    src.filename.match(%r{.+/lib/[^/]+.rb})
  end
end

Dir.chdir(File.dirname(__FILE__)) do
  Dir.glob('test_*.rb').each do |testfile|
    next if File.basename(testfile) == File.basename(__FILE__)
    next if File.basename(testfile).include?('blackbox')
    puts "Adding Test File: #{testfile}"
    require_relative testfile
  end
end

#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redmine/general'
require 'redmine/project'

Dir.chdir(File.dirname(__FILE__))

config     = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: dump_redmine_versions.rb [options]'

  opts.on('-h', '--help', 'Print help') do
    puts opts
    exit(1)
  end

  opts.on('-R name', '--redmine-project=name', 'Identifier of the Redmine project') do |n|
    identifier = n
  end
end.parse!(ARGV)

Redmine.configure do |c|
  raise Exception, 'Redmine not configured in settings.yaml' unless config['redmine']
  config['redmine'].each do |k, v|
    c.public_send("#{k}=", v)
  end
end

raise Exception, 'Redmine project identifier not specified' unless identifier
project = Redmine::Project.find_by_identifier(identifier)

dump = "#{Dir.pwd}/dump"
Dir.mkdir(dump) unless Dir.exists?(dump)
dump = "#{dump}/#{identifier}"
Dir.mkdir(dump) unless Dir.exists?(dump)

#
# Get all RedMine project versions
#
dump_file = "#{dump}/versions.json"

logger.info('Indexing versions from Redmine...')

versions = Redmine::Version.find(:all, params: {
  project_id: project.id,
  status: '*'
})

file = File.open(dump_file, 'w')
file.write(JSON.pretty_generate(JSON.parse(versions.to_json)))
file.close

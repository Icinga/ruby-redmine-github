#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redmine/general'
require 'redmine/project'
require 'github/issue'

Dir.chdir(File.dirname(__FILE__))

config = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil
use_cache = true

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: dump_redmine.rb [options]'

  opts.on('-h', '--help', 'Print help') do
    puts opts
    exit(1)
  end

  opts.on('-R name', '--redmine-project=name', 'Identifier of the Redmine project') do |n|
    identifier = n
  end

  opts.on('--[no-]cache', 'Ignore cached JSON files') do |v|
    use_cache = v
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

Dir.mkdir('dump') unless Dir.exists?('dump')
Dir.mkdir('dump/issues') unless Dir.exists?('dump/issues')

#
# Get all RedMine issues
#
logger.info('Indexing issues from Redmine...')
issues = project.issues(
  project_id: project.id,
  status_id:  '*'
)

logger.info("Found #{issues.length} issues, pulling them all")

issues.each do |i|
  id = i.id
  dump = "#{Dir.pwd}/dump/issues/#{id}"
  json_file = "#{dump}.json"

  issue = nil
  if File.exists?(json_file)
    logger.info("Loading issue \##{id} from cache")
    issue = Github::Issue.from_json(json_file)
  end

  unless issue
    logger.info("Loading issue \##{id} from Redmine")
    issue = Github::Issue.from_redmine(id)
    issue.dump_json("#{dump}.json")
  end

  issue.dump("#{dump}.md")
end

#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'net/http'

require 'redmine/general'
require 'redmine/project'
require 'github/issue'
require 'redminegithub/utils'

Dir.chdir(File.dirname(__FILE__))

config = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil
use_cache = true
only_ids = nil

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: dump_redmine_issues.rb [options]'

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

  opts.on('--issues=list', 'Comma separated list of issue ids to take care of') do |v|
    only_ids = v.split(/\s*,\s*/)
  end
end.parse!(ARGV)

Redmine.configure do |c|
  raise Exception, 'Redmine not configured in settings.yaml' unless config['redmine']
  config['redmine'].each do |k, v|
    c.public_send("#{k}=", v)
  end
end

# add user_map from config to resolve assignees
Redmine::General.user_map = config['user_map'] if config.key?('user_map')

# Load up redmine project
raise Exception, 'Redmine project identifier not specified' unless identifier
project = Redmine::Project.find_by_identifier(identifier)

dump = "#{Dir.pwd}/dump"
Dir.mkdir(dump) unless Dir.exists?(dump)
dump = "#{dump}/#{identifier}"
Dir.mkdir(dump) unless Dir.exists?(dump)
Dir.mkdir("#{dump}/issue") unless Dir.exists?("#{dump}/issue")

attachment_dump = "#{dump}/attachments"
Dir.mkdir(attachment_dump) unless Dir.exists?(attachment_dump)
attachment_dump += "/download"
Dir.mkdir(attachment_dump) unless Dir.exists?(attachment_dump)

#
# Get all RedMine issues
#
dump_file = "#{dump}/issues.json"

# TODO: do this anonymous, so we only get public issues
Redmine.configure do |c|
  c.api_key = ''
end

if use_cache && File.exists?(dump_file)
  logger.info('Getting issues from cache...')

  issues = YAML.parse(File.read(dump_file))
  issues = issues.to_ruby if issues.respond_to?(:to_ruby)
else
  logger.info('Indexing issues from Redmine...')
  issues = project.issues(
    project_id: project.id,
    status_id:  '*'
  ).map do |i| # map only core data
    {
      id: i.id,
      project: i.project.name,
      tracker: i.tracker.name,
      status: i.status.name,
      subject: i.subject
    }
  end

  RedmineGithub::Utils.dump_to_file(dump_file, JSON.pretty_generate(issues))
end

# TODO: reset auth
Redmine.configure do |c|
  c.api_key = config['redmine']['api_key']
end

logger.info("Found #{issues.length} issues")

issues.each do |i|
  id = i['id'] || i[:id]
  next unless only_ids.nil? || only_ids.include?(id.to_s)

  dump_file = "#{dump}/issue/#{id}"
  json_file = "#{dump_file}.json"

  issue = nil
  if use_cache && File.exists?(json_file)
    logger.info("Loading issue \##{id} from cache")
    issue = Github::Issue.from_json(json_file)
  end

  unless issue
    logger.info("Loading issue \##{id} from Redmine")
    issue = Github::Issue.from_redmine(id)
    issue.dump_json(json_file)
  end

  issue.subject_prefix = config['github_subject_prefix'] if config.key?('github_subject_prefix')

  issue.dump("#{dump_file}.md")

  issue.attachments.each do |a|
    dir = "#{attachment_dump}/#{a.id}"
    file = "#{dir}/#{a.filename}"

    Dir.mkdir(dir) unless Dir.exists?(dir)

    unless File.exists?(file) && File.size(file) == a.filesize
      logger.info "Downloading attachment #{a.filename} (size: #{a.filesize}) from #{a.content_url}"

      uri = URI(a.content_url)
      response = Net::HTTP.get_response(uri)

      raise Exception, "Invalid HTTP response: #{response.code}" unless response.code.to_i == 200

      File.open(file, 'wb') do |fh|
        fh.write(response.body)
        fh.close
      end

      logger.info "Attachment saved at: #{file}"
    end

    raise Exception, "file has invalid size: #{File.size(file)} != expected #{a.filesize}" unless File.size(file) == a.filesize

    unless File.exists?("#{file}.json")
      meta = a.as_json
      meta[:issue_id] = id

      File.open("#{file}.json", 'w') do |fh|
        fh.write(JSON.pretty_generate(meta))
        fh.close
      end
    end
  end
end

logger.info 'Done.'

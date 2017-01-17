#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redminegithub/utils'
require 'github/issue'

Dir.chdir(File.dirname(__FILE__))

config     = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil
only_ids   = nil

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: push_redmine_redirect_comments.rb [options]'

  opts.on('-h', '--help', 'Print help') do
    puts opts
    exit(1)
  end

  opts.on('-R name', '--redmine-project=name', 'Identifier of the Redmine project') do |n|
    identifier = n
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

# Load up redmine project
raise Exception, 'Redmine project identifier not specified' unless identifier
project = Redmine::Project.find_by_identifier(identifier)

dump = "#{Dir.pwd}/dump/#{identifier}"
dump_file = "#{dump}/issue_map.json"

raise Exception, "Missing issue map at #{dump_file}" unless File.exists?(dump_file)

logger.info "Loading issue map from #{dump_file}"
issue_map = JSON.parse(File.read(dump_file))

logger.info('Indexing issues from Redmine...')
issues = project.issues(
  project_id: project.id,
  status_id:  'open'
).map do |i| # map only core data
  {
    id: i.id,
    project: i.project.name,
    tracker: i.tracker.name,
    status: i.status.name,
    subject: i.subject
  }
end

logger.info("Found #{issues.length} issues")

issues.each do |i|
  id = i[:id]
  next unless only_ids.nil? || only_ids.include?(id.to_s)

  unless issue_map.key?(id.to_s)
    logger.error "Issue \##{id} not found in Issue map!"
    next
  end

  logger.info("Loading issue \##{id} from Redmine")
  issue = Github::Issue.from_redmine(id)

  # check if redirection comment is already there
  message_pattern = Regexp.quote 'migrated to GitHub'

  html_url = "#{Redmine.configuration.site}/issues/#{id}"

  found = false
  if issue.issue.respond_to?(:journals)
    issue.issue.journals.each do |c|
      next unless c.respond_to?(:notes)
      if c.notes =~ /#{message_pattern}/
        found = c.id
        # TODO: check correct URL?
        logger.info "Found migration comment: #{html_url}"
        break
      end
    end
  end

  unless found
    # need to create comment
    url = issue_map[id.to_s]
    comment = "This issue has been migrated to GitHub.\n\n"\
      "If you want to keep following the status, please ensure you subscribe to the GitHub issue:\n\n#{url}\n"

    uri = URI("#{html_url}.json")
    request = Net::HTTP::Put.new(uri)
    request.body = JSON.unparse(issue: { notes: comment })
    request.content_type = 'application/json'
    request['X-Redmine-API-Key'] = Redmine.configuration.api_key

    response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
      http.request(request)
    end

    raise Exception, "Invalid HTTP response: #{response.code}" unless response.code.to_i == 200

    logger.info "Created migration comment for issue \##{id} #{html_url}"
  end
end

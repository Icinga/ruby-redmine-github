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

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: push_github_issues.rb [options]'

  opts.on('-h', '--help', 'Print help') do
    puts opts
    exit(1)
  end

  opts.on('-R name', '--redmine-project=name', 'Identifier of the Redmine project') do |n|
    identifier = n
  end

  opts.on('-U name', '--github-user=name', 'Name of the GitHub user / organization') do |n|
    config['github']['user'] = n
  end

  opts.on('-P name', '--github-project=name', 'Name of the GitHub repo') do |n|
    config['github']['repo'] = n
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
Redmine::Project.find_by_identifier(identifier)

raise Exception, 'GitHub user not specified' unless config['github']['user']
raise Exception, 'GitHub repo not specified' unless config['github']['repo']

github = RedmineGithub::Utils.github_client(config)

# add user_map from config to resolve assignees
Redmine::General.user_map = config['user_map'] if config.key?('user_map')

dump = "#{Dir.pwd}/dump/#{identifier}"
dump_file = "#{dump}/issues.json"

raise Exception, "Missing cached issues at #{dump_file}" unless File.exists?(dump_file)

logger.info "Loading cached issues from #{dump_file}"

issues = JSON.parse(File.read(dump_file))

logger.info 'Indexing existing GitHub issues...'

opts = { user: config['github']['user'], repo: config['github']['repo']}
issues_existing = github.issues.list(opts.merge(state: 'all'))

issue_by_redmine_id = {}
issues_existing.each do |i|
  next unless i.title =~ /^\[Redmine #(\d+)\]/
  redmine_id = $1.to_i
  raise Exception, "Duplicate Redmine issue in Github: #{redmine_id} #{i.url}" if issue_by_redmine_id.key?(redmine_id)
  issue_by_redmine_id[redmine_id] = i
end

logger.info 'Indexing milestones'

milestone_map = {}
milestones = github.issues.milestones.list(opts.merge(state: 'all'))
milestones.each do |m|
  milestone_map[m.title] = m.number
end

logger.info 'Working on issues...'

issues.each do |v|
  json_file = "#{dump}/issue/#{v['id']}.json"
  issue = Github::Issue.from_json(json_file)

  if issue_by_redmine_id.key?(issue.id)
    i = issue_by_redmine_id[issue.id]

    changes = {}

    %w(title state body).each do |f|
      value = issue.send(f)
      current = i.send(f)
      changes[f.to_sym] = value if current != value
    end

    # assignee(s)
    current = i.assignees.map { |n| n.login }
    changes[:assignee] = issue.assignee unless issue.assignee.nil? || current.include?(issue.assignee)

    # milestone
    if issue.milestone
      raise Exception, "Could not find milestone #{issue.milestone}" unless milestone_map.key?(issue.milestone)
      milestone_number = milestone_map[issue.milestone]
      changes[:milestone] = milestone_number if i.milestone.nil? || i.milestone.number != milestone_number
    end

    # labels
    old_labels = i.labels.map { |l| l.name }
    new_labels = issue.labels.select { |l| !old_labels.include?(l) }
    changes[:labels] = old_labels + new_labels unless new_labels.empty?

    if changes.empty?
      logger.info "Issue \##{i.number} already exists: #{issue.title} - #{i.html_url}"
    else
      logger.info "Updating issue \"#{i.title}\" #{i.html_url}: #{changes.inspect}"

      github.issues.edit(changes.merge(number: i.number))

      # As suggested by GitHub
      # https://developer.github.com/guides/best-practices-for-integrators/#dealing-with-abuse-rate-limits
      sleep(1)
    end
  else
    logger.info "Creating issue \"#{issue.title}\""
    data = issue.to_hash

    # TODO: assignee set on creation?

    # milestone
    if data[:milestone]
      raise Exception, "Could not find milestone #{issue.milestone}" unless milestone_map.key?(issue.milestone)
      data[:milestone] = milestone_map[issue.milestone]
    end

    i = github.issues.create(data)
    logger.info "Issue \##{i.number} created: #{issue.title} - #{issue.html_url}"

    # As suggested by GitHub
    # https://developer.github.com/guides/best-practices-for-integrators/#dealing-with-abuse-rate-limits
    sleep(1)

    if issue.state == 'closed'
      github.issues.edit(number: i.number, state: 'closed')
      logger.info "Closed issue #{i.number} since original issue is done"
    end
  end
end

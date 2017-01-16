#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redminegithub/utils'
require 'github_api'
require 'github_api/client/import' # NOTE: This patches github_api and is needed
require 'github/issue'

Dir.chdir(File.dirname(__FILE__))

config     = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil
only_ids   = nil

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

# Indexing existing issues
issue_by_redmine_id = {}
issue_number_to_redmine = {}

github.issues.list(opts.merge(state: 'all')) do |i|
  next unless i.title =~ /^\[[^\]]+ #(\d+)\]/
  unless only_ids.nil?
    next unless only_ids.include?($1)
  end
  redmine_id = $1.to_i
  raise Exception, "Duplicate Redmine issue in Github: #{redmine_id} #{i.url}" if issue_by_redmine_id.key?(redmine_id)
  issue_by_redmine_id[redmine_id] = i
  issue_number_to_redmine[i.number.to_i] = redmine_id
end

# Indexing comments by issue
comments_existing = {}
if config['github_api_import']
  logger.info 'Indexing existing comments on issues...'
  github.issues.comments.list do |c|
    prefix = Regexp.quote("/#{opts[:user]}/#{opts[:repo]}/")
    raise Exception, "Invalid issue url: #{c.issue_url}" unless c.issue_url =~ /#{prefix}issues\/(\d+)$/
    number = $1.to_i
    next unless issue_number_to_redmine.key?(number)
    comments_existing[number] = [] unless comments_existing.key?(number)
    comments_existing[number] << c
  end
end

logger.info 'Indexing milestones'

milestone_map = {}
milestones = github.issues.milestones.list(opts.merge(state: 'all'))
milestones.each do |m|
  milestone_map[m.title] = m.number
end

logger.info 'Working on issues...'

# Record ID mappings
# Redmine # -> GitHub URL
issue_map = {}

# Check for pending issues
is_pending = false
if config['github_api_import']
  logger.info 'Checking for pending issues in import...'
  pending = 0
  # TODO: filter by status possible?
  github.import.issues.list { |i| pending += 1 if i.status == 'pending' }
  if pending > 0
    logger.error "There are #{pending} imported issues, we need to wait for them to complete/fail..."
    exit(1)
  end
end

issues.each do |v|
  next unless only_ids.nil? || only_ids.include?(v['id'].to_s)

  json_file = "#{dump}/issue/#{v['id']}.json"
  issue = Github::Issue.from_json(json_file)
  issue.use_inline_comments = false if config['github_api_import']
  issue.subject_prefix = config['github_subject_prefix'] if config.key?('github_subject_prefix')

  if issue_by_redmine_id.key?(issue.id)
    existing = issue_by_redmine_id[issue.id]

    changes = {}

    %w(title state body).each do |f|
      value = issue.send(f)
      current = existing.send(f)
      changes[f.to_sym] = value if current != value
    end

    # assignee(s)
    current = existing.assignees.map { |n| n.login }
    changes[:assignee] = issue.assignee unless issue.assignee.nil? || current.include?(issue.assignee)

    # milestone
    if issue.milestone
      raise Exception, "Could not find milestone #{issue.milestone}" unless milestone_map.key?(issue.milestone)
      milestone_number = milestone_map[issue.milestone]
      changes[:milestone] = milestone_number if existing.milestone.nil? || existing.milestone.number != milestone_number
    end

    # labels
    old_labels = existing.labels.map { |l| l.name }
    new_labels = issue.labels.select { |l| !old_labels.include?(l) }
    changes[:labels] = old_labels + new_labels unless new_labels.empty?

    issue_map[issue.id] = existing.html_url
    if changes.empty?
      logger.info "Issue \##{existing.number} already exists: #{issue.title} - #{existing.html_url}"
    else
      logger.info "Updating issue \"#{existing.title}\" #{existing.html_url}: #{changes.inspect}"

      github.issues.edit(changes.merge(number: existing.number))

      # As suggested by GitHub
      # https://developer.github.com/guides/best-practices-for-integrators/#dealing-with-abuse-rate-limits
      sleep(0.5)
    end

    # Do we need to update / create comments?
    if config['github_api_import']
      issue.comments.each do |c|
        timestamp = DateTime.parse(c[:created_at])
        found = false

        comments_existing[existing.number].each do |ec|
          # TODO: match user!
          unless ec.body =~ /^\*\*Updated by .+ on (.+)\*\*\r?$/
            raise Exception, "Could not find timestamp in comment: #{ec.inspect}"
          end
          if DateTime.parse($1) == timestamp
            # found matching comment
            unless ec.body == c[:body]
              data = { body: c[:body] }
              logger.info "Updating comment #{ec.id} on issue #{existing.number} - #{ec.html_url} - #{data.inspect}"
              github.issues.comments.edit data.merge(id: ec.id)
            end
            found = true
            break
          end
        end if comments_existing.key?(existing.number)

        unless found
          data = { body: c[:body] }
          ec = github.issues.comments.create data.merge(number: existing.number)
          logger.info "Created comment #{ec.id} on issue #{existing.number} - #{ec.html_url} - #{data.inspect}"
        end
      end
    end
  else
    logger.info "Creating issue \"#{issue.title}\""
    data = issue.to_hash

    # milestone
    if data[:milestone]
      raise Exception, "Could not find milestone #{issue.milestone}" unless milestone_map.key?(issue.milestone)
      data[:milestone] = milestone_map[issue.milestone]
    end

    if config['github_api_import']
      import_data = { issue: data.merge(created_at: issue.created_at) }
      import_data[:issue].delete(:state)

      if issue.state == 'closed'
        import_data[:issue][:closed_at] = issue.closed_at
        import_data[:issue][:closed] = true
      end

      import_data[:comments] = issue.comments

      github.import.issues.create(import_data)
      is_pending = true
    else
      created = github.issues.create(data)
      logger.info "Issue \##{created.number} created: #{issue.title} - #{issue.html_url}"
      issue_map[issue.id] = created.html_url

      # As suggested by GitHub
      # https://developer.github.com/guides/best-practices-for-integrators/#dealing-with-abuse-rate-limits
      sleep(1)

      if issue.state == 'closed'
        github.issues.edit(number: created.number, state: 'closed')
        logger.info "Closed issue #{created.number} since original issue is done"
      end
    end
  end
end

if is_pending
  logger.warn 'Can not write issue map, some issues where just imported, or are pending!'
  exit(1)
else
  # dump issue map to file
  File.open(file = "#{dump}/issue_map.json", 'w') do |fh|
    logger.info "Dumping issue map to #{file}"
    fh.write(JSON.pretty_generate(issue_map))
    fh.close
  end

  File.open(file = "#{dump}/issue_map.txt", 'w') do |fh|
    logger.info "Dumping issue map to #{file}"
    str = ''
    issue_map.each do |k, v|
      str += "#{k}\t#{v}\n"
    end
    fh.write(str)
    fh.close
  end
end

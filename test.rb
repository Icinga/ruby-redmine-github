#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'redmine/general'
require 'redmine/project'
require 'github_api'
require 'github/issue'

Redmine.configure do |config|
  config.api_key = 'XXX'
  config.site    = 'https://dev.icinga.com'
end

github = Github.new(
  oauth_token: 'XXX',
  user: 'lazyfrosch',
  repo: 'redmine-test'
)

project = Redmine::Project.find_by_identifier('i2')

# status = Redmine::General.status
# status_open = status.keys.select { |id| !Redmine::General.status_closed.include?(id) }

#
# Index all GitHub issues
#
gh_issues = github.issues.list(state: 'all')
existing = {}
all = {}
other = {}
gh_issues.each do |issue|
  all[issue[:number]] = issue
  if issue[:title] =~ /Redmine #(\d+)/
    existing[Regexp.last_match[1]] = issue
  else
    other[issue[:number]] = issue
  end
end

#
# Get all RedMine issues
#
issues = project.issues(
  project_id: project.id,
  status_id:  'open',
  limit:      10
)

issues.each do |i|
  issue = Github::Issue.new(i)

  body = "This issue has been migrated from Icinga's Redmine Installation:\n"
  body += "#{Redmine.configuration.site}/issues/#{issue.redmine_id}\n\n"
  body += "Author: #{issue.author}\n"
  # TODO: other data
  body += "\n"
  body += issue.description

  if existing.has_key?(issue.redmine_id)
    issue_existing = existing[issue.redmine_id]
    changes = {}
    changes[:body] = body if body != issue_existing.body

    github.issues.edit(changes.merge(number: issue.number)) unless changes.empty?
  else
    github.issues.create(
      title: issue.subject,
      body: body,
      labels: issue.labels
    )
  end


  #puts issue
  #puts '#' * 80
end

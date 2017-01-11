#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'optparse'
require 'yaml'
require 'redminegithub/utils'
require 'github/milestone'

Dir.chdir(File.dirname(__FILE__))

config     = YAML.parse(File.read('settings.yml')).to_ruby
identifier = nil

logger = Logger.new(STDERR)

OptionParser.new do |opts|
  opts.banner = 'Usage: push_github_milestones.rb [options]'

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

raise Exception, 'Redmine project identifier not specified' unless identifier
raise Exception, 'GitHub user not specified' unless config['github']['user']
raise Exception, 'GitHub repo not specified' unless config['github']['repo']

github = RedmineGithub::Utils.github_client(config)

dump_file = "#{Dir.pwd}/dump/#{identifier}/versions.json"

raise Exception, "Missing cached versions at #{dump_file}" unless File.exists?(dump_file)

logger.info "Loading cached versions from #{dump_file}"

versions = JSON.parse(File.read(dump_file))

opts = { user: config['github']['user'], repo: config['github']['repo']}
milestones = github.issues.milestones.list(opts.merge(state: 'all'))

ms_by_title = {}
milestones.each do |ms|
  raise Exception, "Milestone title \"#{ms.title}\" is duplicated!" if ms_by_title[ms.title]
  ms_by_title[ms.title] = ms
end

versions.each do |v|
  milestone = Github::Milestone.new(github, v)

  if ms_by_title.key?(milestone.title)
    ms = ms_by_title[milestone.title]
    logger.info "Milestone exists: #{ms.number} \"#{ms.title}\" #{ms.url}"
    # TODO: edit?
  else
    logger.info "Creating milestone \"#{milestone.title}\""
    ms = github.issues.milestones.create(milestone.to_hash)
    logger.info "Created milestone #{ms.number} \"#{ms.title}\""
  end
end

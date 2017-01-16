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

dump = "#{Dir.pwd}/dump/#{identifier}"
dump_file = "#{dump}/versions.json"

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

version_map = {}

versions.each do |v|
  milestone = Github::Milestone.new(github, v)

  if ms_by_title.key?(milestone.title)
    ms = ms_by_title[milestone.title]

    changes = {}
    %w(description state due_on).each do |f|
      value = milestone.send(f)
      current = ms.send(f)
      if f == 'due_on' && value != nil
        # only compare date part, GitHub does not property handle UTC timestamps, also see Github::Milestone
        value.gsub!(/T\d{2}:\d{2}:\d{2}.*$/, '')
        current.gsub!(/T\d{2}:\d{2}:\d{2}.*$/, '')
      end
      changes[f] = value if current != value
    end

    if changes.empty?
      logger.info "Milestone exists: #{ms.number} \"#{ms.title}\" #{ms.html_url}"
    else
      logger.info "Updating milestone \"#{ms.title}\" #{ms.html_url}: #{changes.inspect}"
      github.issues.milestones.update(changes.merge(number: ms.number))
    end
  else
    logger.info "Creating milestone \"#{milestone.title}\""
    ms = github.issues.milestones.create(milestone.to_hash)
    logger.info "Created milestone #{ms.number} \"#{ms.title}\": #{ms.html_url}"
  end

  version_map[v['version']['id']] = ms.html_url
end

# dump issue map to file
File.open(file = "#{dump}/version_map.json", 'w') do |fh|
  logger.info "Dumping version map to #{file}"
  fh.write(JSON.pretty_generate(version_map))
  fh.close
end

File.open(file = "#{dump}/version_map.txt", 'w') do |fh|
  logger.info "Dumping version map to #{file}"
  str = ''
  version_map.each do |k, v|
    str += "#{k}\t#{v}\n"
  end
  fh.write(str)
  fh.close
end

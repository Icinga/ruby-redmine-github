require 'github_api'

require 'github/utils'

module Github
  class Issue
    attr_reader :issue

    attr_accessor :labels, :subject, :description

    def initialize(data)
      @issue = data

      # TODO: assigned?
      # TODO: categories
      # TODO: private
      # TODO: target version

      @subject = "[Redmine ##{@issue.id}] #{@issue.subject}"
      redmine_labels
      redmine_description
    end

    def self.from_redmine(id)
      new(Redmine::Issue.find(id, params: {
        include: %w(changesets children attachments relations journals).join(',')
      }))
    end

    def self.from_json(file)
      file = File.open(file, 'r') unless file.respond_to?(:read)
      issue = Redmine::Issue.new
      issue.load(JSON.parse(file.read))
      new(issue)
    end

    def to_s
      [subject, "Labels: #{labels.join(', ')}", '-' * 80, markdown].join("\n")
    end

    def dump_json(file)
      data = @issue.to_json
      data = JSON.parse(data)
      data = JSON.pretty_generate(data)
      GitHub::Utils.dump_to_file(file, data)
    end

    def dump_markdown(file)
      GitHub::Utils.dump_to_file(file, markdown)
    end

    def dump(file)
      GitHub::Utils.dump_to_file(file, to_s)
    end

    def markdown
      # TODO:
      "This issue has been migrated from Icinga's Redmine Installation:\n"
      +"#{Redmine.configuration.site}/issues/#{@issue.id}\n\n"
      +"Author: #{@issue.author.name}\n"
      +"\n---\n"
      +description
    end

    protected

    def redmine_labels
      @labels = ['imported']
      @labels << 'Feedback' if @issue.status.name == 'Feedback'
      @labels << @issue.priority.name if @issue.priority.name != 'Normal'
      @labels << @issue.tracker.name if @issue.tracker.name != 'Bug'
    end

    def redmine_description
      # TODO: convert to markdown?
      @description = @issue.description
      @description.gsub!(/(\\r)?\\n/, "\n") # escaped new lines
      @description.gsub!(/^/m, '    ') # as markdown code
      # @code_blocks = []
      # d.gsub!(/<pre>(.*?)<\/pre>/) do |m|
      #   @code_blocks << m
      #   "CODEBLOCK<<#{@code_blocks.size - 1}>>"
      # end
      #
      # d.gsub!(/(\\r)?\\n/, "\n") # escaped new lines
      # d.gsub!(/^\s*h(\d)\.\s+(.+)$/m) do # header
      #   m = Regexp.last_match
      #   "#{'#' * m[1].to_i} #{m[2]}"
      # end
      # d.gsub!(/\*(.*?)\*/, '**\1**') # bold
      # d.gsub!(/@(.*?)@/, '`\1`') # inline code
      # #d.gsub!(/\s*<pre>(.+)?<\/pre>\s*/is, "\n\n```\n\1\n```\n\n")
      # @description = d
    end
  end
end
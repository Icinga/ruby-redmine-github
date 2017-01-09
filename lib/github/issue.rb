require 'github_api'

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

    def to_s
      [ subject, "Labels: #{labels.join(', ')}", '-' * 80, description ].join("\n")
    end

    def redmine_id
      @issue.id
    end

    def author
      @issue.author.name
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
require 'github_api'

require 'redminegithub/utils'
require 'redmine/general'
require 'redmine/markdown_converter'

module Github
  class Issue
    attr_reader :issue
    attr_writer :title, :body, :assignee, :labels, :milestone

    def initialize(data)
      @issue = data
      raise Exception, 'Private issues can not be migrated!' if @issue.is_private
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
      markdown
    end

    def dump_json(file)
      data = @issue.to_json
      data = JSON.parse(data)
      data = JSON.pretty_generate(data)
      RedmineGithub::Utils.dump_to_file(file, data)
    end

    def dump_markdown(file)
      RedmineGithub::Utils.dump_to_file(file, markdown)
    end

    def dump(file)
      RedmineGithub::Utils.dump_to_file(file, to_s)
    end

    def markdown
      [
        "    Title: #{title}",
        "    Labels: #{labels.join(', ')}",
        "    Assignee: #{assignee}",
        "    Milestone: #{milestone}",
        '',
        body
      ].join("\n")
    end

    def state
      # TODO: closed?
    end

    def title
      @title ||= "[Redmine ##{@issue.id}] #{@issue.subject}"
    end

    def body
      unless @body
        @body = <<-END.gsub(/^ {10}/, '')
          This issue has been migrated from Redmine: #{Redmine.configuration.site}/issues/#{@issue.id}

              Author: #{@issue.author.name}
              Assignee: #{@issue.respond_to?(:assigned_to) ? @issue.assigned_to.name : '(none)'}
              Target Version: #{@issue.respond_to?(:fixed_version) ? @issue.fixed_version.name : '(none)'}
              Created: #{@issue.created_on}#{@issue.respond_to?(:closed_on) ? " (closed on #{@issue.closed_on})" : ''}
              Last Update: #{@issue.updated_on} (in Redmine)
        END

        @body += redmine_custom_fields
        @body += "\n---\n\n"
        @body += redmine_description

        @body += "\n---\n\n"
        # TODO: parents
        # TODO: subtasks
        # TODO: relations
        @body += "\n---\n\n"
        @body += redmine_journal
      end
      @body
    end

    def labels
      unless @labels
        @labels = ['imported']
        %w(status priority tracker category).each do |k|
          l = send("labels_#{k}")
          @labels << l unless l.nil? || l.empty?
        end
      end
      @labels
    end

    def assignee
      # TODO:
      nil
    end

    def milestone
      # TODO: resolve number
      nil
    end

    protected

    def labels_status
      case @issue.status.name
        when 'Feedback'
          ['feedback']
        else
          nil
      end
    end

    def labels_priority
      @issue.priority.name == 'Normal' ? nil : @issue.priority.name
    end

    def labels_tracker
      case name = @issue.tracker.name
        when 'Bug'
          ['bug']
        when 'Feature'
          ['enhancement']
        else
          # TODO: this might hit with Support
          raise Exception, "Unhandled tracker name #{name}"
      end
    end

    def labels_category
      @issue.respond_to?(:category) ? [@issue.category.name] : nil
    end

    def redmine_description
      Redmine::MarkdownConverter.convert(@issue.description.strip)
    end

    def redmine_journal
      journal = []

      @issue.journals.each do |j|
        entry = "**Updated by #{j.user.name} on #{j.created_on}**\n\n"
        if j.details
          j.details.each { |d| entry += "* #{redmine_journal_detail(d)}\n" }
          entry += "\n"
        end

        entry += Redmine::MarkdownConverter.convert(j.notes) if j.respond_to?(:notes)
        journal << entry
      end
      journal.join("\n---\n\n")
    end

    def redmine_journal_detail(detail)
      case detail.property
        when 'attachment'
          "File added _#{detail.new_value}_"
        when 'attr'
          term  = if detail.respond_to?(:old_value)
            "changed from _#{Redmine::General.attr_value(detail.name, detail.old_value)}_"
          else
            'set'
          end
          new_value = Redmine::General.attr_value(detail.name, detail.new_value)
          "**#{Redmine::General.attr(detail.name)}** #{term} to _#{new_value}_"
        else
          raise Exception, "Unknown journal detail property: #{d.property}"
      end
    end

    def redmine_custom_fields
      str = ''
      if @issue.custom_fields
        str += "\n"
        @issue.custom_fields.each do |field|
          str += "    #{field.name}: #{field.value}\n" if field.respond_to?(:value) && !field.value.empty?
        end
      end
      str
    end
  end
end
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
              Status: #{@issue.status.name}
              Target Version: #{@issue.respond_to?(:fixed_version) ? @issue.fixed_version.name : '(none)'}
              Created: #{@issue.created_on}#{@issue.respond_to?(:closed_on) ? " (closed on #{@issue.closed_on})" : ''}
              Last Update: #{@issue.updated_on} (in Redmine)
        END

        @body += redmine_custom_fields
        @body += "\n---\n\n"
        @body += redmine_description

        @body += "\n---\n\n"
        @body += redmine_relations
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

    def redmine_link(issue_id, title = nil)
      title = "\##{issue_id}" unless title
      "[#{title}](#{Redmine.configuration.site}/issues/#{issue_id})"
    end

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
        when 'attr', 'cf', 'relation'
          if detail.name == 'description'
            term = 'updated'
          else
            value_old = detail.respond_to?(:old_value) ? Redmine::General.attr_value(detail.name, detail.old_value) : nil
            value_new = detail.respond_to?(:new_value) ? Redmine::General.attr_value(detail.name, detail.new_value) : nil

            term = if value_old && value_new
              "changed from _#{value_old}_ to _#{value_new}_"
            elsif value_old
              "deleted ~~#{value_old}~~"
            elsif value_new
              "set to _#{value_new}_"
            else
              raise Exception, "Invalid detail: #{detail.inspect}"
            end
          end

          name = if detail.property == 'cf'
            field_name = '(unknown custom field)'
            @issue.custom_fields.each do |field|
              if field.id == detail.name.to_i
                field_name = field.name
                break
              end
            end
            field_name
          else
            Redmine::General.attr(detail.name)
          end
          "**#{name}** #{term}"
        else
          raise Exception, "Unknown journal detail property: #{detail.inspect}"
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

    def redmine_relations
      str = ''
      str += "**Parent Task:** #{redmine_link(@issue.parent.id)}\n\n" if @issue.respond_to?(:parent)

      # child issues
      if @issue.respond_to?(:children) && !@issue.children.empty?
        str += "**Subtasks**:\n\n"
        @issue.children.each do |c|
          str += "* #{redmine_link(c.id, "#{c.tracker.name} #{c.id} - #{c.subject}")}\n"
        end
        str += "\n"
      end

      # relations to other issues
      if @issue.respond_to?(:relations) && !@issue.relations.empty?
        str += "**Relations**:\n\n"
        @issue.relations.each do |r|
          str += "* #{r.relation_type} #{redmine_link(r.issue_to_id)}\n"
        end
        str += "\n"
      end
      str += "\n---\n\n" unless str == ''
      str
    end
  end
end
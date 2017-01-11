require 'github_api'

module Github
  class Milestone
    attr_reader :version, :github

    def initialize(github, data)
      @github = github
      @version = data['version']
    end

    def title
      @version['name']
    end

    def description
      "Imported from Redmine\n\n" + @version['description']
    end

    def due_on
      return nil unless @version['due_date']
      @version['due_date'] + 'T00:00:00Z'
    end

    # TODO: do we need open for import?
    def state
      @version['status'] == 'closed' ? 'closed' : 'open'
    end

    def to_s
      sep = '-' * 80
      [title, sep, description, sep, "State: #{state}", "Due on: #{due_on}"].join("\n")
    end

    def to_hash
      hash = {}
      %w(title description due_on state).each do |key|
        hash[key.to_sym] = send(key)
      end
      hash
    end
  end
end
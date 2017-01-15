require 'redmine/custom'
require 'redmine/project'

module Redmine
  module General
    @attr_map = {
      tracker_id:       'Tracker',
      status_id:        'Status',
      priority_id:      'Priority',
      project_id:       'Project',
      fixed_version_id: 'Target Version',
      assigned_to_id:   'Assigned to',
      done_ratio:       'Done %',
      category_id:      'Category',
    }.freeze

    def self.attr(attr)
      unless @attr_map.key?(attr.to_sym)
        return attr.sub(/^(\w)/) { |s| s.capitalize }
          .sub(/_(\w)/) { |s| " #{$1.capitalize}" }
      end
      @attr_map[attr.to_sym]
    end

    def self.attr_value(attr, value)
      return value if value.to_i == 0
      value = value.to_i
      if attr =~ /_id$/
        name = attr.gsub(/_id$/, '')

        return value if name == 'parent'
        return send(name, value) unless method(name).parameters.empty?

        list = send(name)
        return value if list.nil?
        raise Exception, "Attr resolution for #{attr} is not a Hash: #{list.inspect}" unless list.is_a?(Hash)
        list[value] || value
      else
        value
      end
    end

    def self.user_map=(map)
      @user_map = map
    end

    def self.user_map
      @user_map
    end

    def self.github_user(redmine_user)
      return nil unless user_map.key?(redmine_user)
      user_map[redmine_user]
    end

    def self.tracker
      lookup('tracker')
    end

    def self.status
      @status_closed = {} unless @status_closed
      lookup('status', class_name: 'IssueStatuses') do |s|
        @status_closed[s.id] = s.name if s.respond_to?(:is_closed) && s.is_closed
      end
    end

    def self.status_id
      return @status_id if @status_id
      status
      @status_id
    end

    def self.status_closed
      return @status_closed if @status_closed
     status
      @status_closed
    end

    def self.category
      # TODO: fix this evil hack
      project = Redmine::Project.instance
      lookup('category', class_name: 'IssueCategories', params: { project_id: project.id })
    end

    def self.project
      lookup('project')
    end

    def self.projects
      return if @projects
      @projects = Redmine::Project.find(:all)
    end

    def self.priority
      lookup('priority', class_name: 'IssuePriorities')
    end

    def self.fixed_version
      # TODO: fix this evil hack
      project = Redmine::Project.instance
      lookup('version', params: { project_id: project.id })
    end

    def self.assigned_to(user_id)
      user_id = user_id.to_i
      @users  = {} unless @users
      return @users[user_id] if @users.key?(user_id)

      user = Redmine::User.find(user_id)

      return @users[user_id] = '(unknown)' if user.nil?
      @users[user_id] = user.login
    end

    # Format ISO 8601 date into a more human friendly form
    # https://de.wikipedia.org/wiki/ISO_8601
    def self.format_date(date)
      return nil if date.nil?
      date = DateTime.parse(date) unless date.is_a?(DateTime)
      date.strftime('%F %T %Z')
      #return date.gsub!(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(.*)$/) { "#{$1} #{$2} #{$3 == 'Z' ? 'UTC' : $3 }" }
    end

    protected

    def self.lookup(name, opts = {}, &block)
      var    = "@#{name}"
      var_id = "@#{name}_id"
      return instance_variable_get(var) if instance_variable_defined?(var)

      real_var          = instance_variable_set(var, {})
      real_var_id       = instance_variable_set(var_id, {})

      opts[:name_attr]  = 'name' unless opts.key?(:name_attr)
      opts[:class_name] = name.sub(/^(\w)/) { |s| s.capitalize } unless opts.key?(:class_name)
      real_class        = Redmine.const_get(opts[:class_name])

      find_opts = opts.key?(:params) ? { params: opts[:params] } : {}
      real_class.find(:all, find_opts).each do |v|
        name              = v.send(opts[:name_attr])
        real_var[v.id]    = name
        real_var_id[name] = v.id
        yield(v) if block
      end
      real_var
    end
  end
end
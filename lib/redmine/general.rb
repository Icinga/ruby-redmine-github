module Redmine
  module General
    def self.tracker
      return @tracker if @tracker

      @tracker = {}
      @tracker_id = {}

      Redmine::Tracker.find(:all).each do |t|
        @tracker[t.id] = t.name
        @tracker_id[t.name] = t.id
      end
    end

    def self.status
      return if @status

      @status = {}
      @status_id = {}
      @status_closed = []

      Redmine::IssueStatuses.find(:all).each do |s|
        @status[s.id] = s.name
        @status_id[s.name] = s.id
        @status_closed << s.id if s.respond_to?(:is_closed) && s.is_closed
      end
      @status
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

    def self.projects
      return if @projects
      @projects = Redmine::Project.find(:all)
    end
  end
end
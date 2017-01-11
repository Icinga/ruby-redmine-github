require 'redmine'
require 'redmine/custom'

module Redmine
  class Project < Redmine::Base
    def self.find_by_identifier(identifier)
      # TODO: fix this nasty workaround
      raise Exception, 'You can only initialize one project at the moment' if defined?(@@instance)
      Redmine::General.projects.each do |p|
        if p.identifier == identifier
          @@instance = p
          break
        end
      end
      raise ArgumentError, "Project #{name} not found" if @@instance.nil?
      @@instance
    end

    def self.instance
      raise Exception, 'Not yet instantiated' unless @@instance
      @@instance
    end

    def issues(params = {})
      params[:limit] = nil unless params[:limit]
      params[:project_id] = @attributes[:id]
      _offset = 0

      issues = []

      while params[:limit].nil? || issues.size < params[:limit]
        _limit = (params[:limit].nil? || params[:limit] > 100) ? 100 : (params[:limit] - _offset)

        _params = params.merge(offset: _offset, limit: _limit)
        page = Redmine::Issue.find(:all, params: _params)
        _offset += _limit

        issues += page.to_a
        break if page.size == 0 || page.size < _limit
      end
      issues
    end

    # TODO: implement
    # def versions
    #   @versions ||= Redmine::Version.find(:all, params: { :project_id => @@instance.id })
    # end
  end
end
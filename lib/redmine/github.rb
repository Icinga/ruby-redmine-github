require 'redmine/custom'

module Redmine::GitHub

  def self.project(name)
    project = nil
    Redmine::General.projects.each do |p|
      if p.identifier == name
        project = p
        break
      end
    end
    raise ArgumentError, "Project #{name} not found" if project.nil?
    project
  end

  def self.issues

  end
end

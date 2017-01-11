require 'redmine'

class Redmine::Tracker < Redmine::Base
end

class Redmine::IssueStatuses < Redmine::Base
end

class Redmine::Version < Redmine::Base
  self.prefix = '/projects/:project_id/'
end

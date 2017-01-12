require 'redmine'

class Redmine::Tracker < Redmine::Base
end

class Redmine::IssueStatuses < Redmine::Base
end

class Redmine::User < Redmine::Base
end

class Redmine::IssuePriorities < Redmine::Base
  self.prefix = '/enumerations/'
end

class Redmine::Version < Redmine::Base
  self.prefix = '/projects/:project_id/'
end

class Redmine::IssueCategories < Redmine::Base
  self.prefix = '/projects/:project_id/'
end

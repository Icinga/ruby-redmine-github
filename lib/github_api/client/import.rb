# encoding: utf-8

Github::Client.namespace :import

module Github
  class Client::Import < API
    require_all 'github_api/client/import', 'issues'

    namespace :issues
  end
end

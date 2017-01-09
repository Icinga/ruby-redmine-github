$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'redmine'

Redmine.configure do |config|
  config.api_key = '1234'
  config.site    = 'http://localhost:8080'
end

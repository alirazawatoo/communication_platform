require 'bundler/setup'
require 'json'
require 'net/http'

Bundler.require(:default)

require_relative '../communication_app'

Dir[File.expand_path('../lib/email_services/*.rb', __dir__)].sort.each { |file| require file }
Dir[File.expand_path('../models/*.rb', __dir__)].sort.each { |file| require file }

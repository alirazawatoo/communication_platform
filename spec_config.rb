ENV['RACK_ENV'] = 'test'
# Fake provider credentials: set before dotenv loads so a local .env never leaks real keys into specs.
ENV['SG_KEY'] = 'test-sendgrid-key'
ENV['POSTMARK_TOKEN'] = 'test-postmark-token'
require './config/application.rb'
require 'rspec'
require 'rack/test'

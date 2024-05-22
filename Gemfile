source 'https://rubygems.org'

ruby file: '.ruby-version'

gem 'sinatra', '~> 4.1', require: 'sinatra/base'
gem 'activerecord', '~> 8.0'
gem 'sinatra-activerecord', '~> 2.0', require: 'sinatra/activerecord'
gem 'pg', '~> 1.6'
gem 'dotenv', '~> 3.1', require: 'dotenv/load'

gem 'puma', '~> 8.0'
gem 'rackup', '~> 2.2'
gem 'rake', '~> 13.2'

group :test do
  gem 'rspec', '~> 3.13'
  gem 'rack-test', '~> 2.1', require: 'rack/test'
  gem 'database_cleaner', '~> 2.1'
  gem 'faker', '~> 3.5'
  gem 'factory_bot', '~> 6.5'
  gem 'webmock', '~> 3.25'
end

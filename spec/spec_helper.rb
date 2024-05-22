require './spec_config'
require 'webmock/rspec'
require 'database_cleaner'
require 'factory_bot'
require 'faker'

WebMock.disable_net_connect!

module ProviderStubs
  SENDGRID_URL = 'https://api.sendgrid.com/v3/mail/send'.freeze
  POSTMARK_URL = 'https://api.postmarkapp.com/email'.freeze

  def stub_sendgrid(status: 202, body: '')
    stub_request(:post, SENDGRID_URL).to_return(status: status, body: body)
  end

  def stub_postmark(status: 200, body: '{"ErrorCode":0,"Message":"OK"}')
    stub_request(:post, POSTMARK_URL).to_return(status: status, body: body)
  end
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ProviderStubs

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
    DatabaseCleaner.strategy = :transaction
    FactoryBot.find_definitions
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end
end

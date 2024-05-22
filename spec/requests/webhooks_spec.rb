require 'spec_helper'

RSpec.describe 'provider webhooks' do
  include Rack::Test::Methods

  def app
    CommunicationApp
  end

  it 'logs a SendGrid event' do
    events = [{ event: 'delivered', email: 'ada@example.com', sg_message_id: 'abc' }]
    post '/sg_webhook', events.to_json, 'CONTENT_TYPE' => 'application/json'

    expect(WebhookLog.last).to have_attributes(service: 'sendgrid', event: 'delivered', email: 'ada@example.com')
  end

  it 'logs a Postmark bounce' do
    bounce = { RecordType: 'Bounce', Email: 'ada@example.com', Type: 'HardBounce' }
    post '/pm_webhook', bounce.to_json, 'CONTENT_TYPE' => 'application/json'

    expect(WebhookLog.last).to have_attributes(service: 'postmark', event: 'Bounce', email: 'ada@example.com')
  end
end

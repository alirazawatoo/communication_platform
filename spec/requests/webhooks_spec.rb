require 'spec_helper'

RSpec.describe 'provider webhooks' do
  include Rack::Test::Methods

  def app
    CommunicationApp
  end

  def post_json(path, payload)
    post path, payload.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  describe 'POST /sg_webhook' do
    it 'logs a SendGrid event' do
      post_json '/sg_webhook', [{ event: 'delivered', email: 'ada@example.com', sg_message_id: 'abc' }]

      expect(WebhookLog.last).to have_attributes(service: 'sendgrid', event: 'delivered', email: 'ada@example.com')
    end

    it 'logs every event in a batch, not just the first' do
      post_json '/sg_webhook', [
        { event: 'processed', email: 'ada@example.com' },
        { event: 'delivered', email: 'ada@example.com' },
        { event: 'open', email: 'grace@example.com' }
      ]

      expect(WebhookLog.pluck(:event)).to contain_exactly('processed', 'delivered', 'open')
      expect(JSON.parse(last_response.body)['logged']).to eq 3
    end

    it 'answers 400 when the body is not an event array' do
      post_json '/sg_webhook', { event: 'delivered' }

      expect(last_response.status).to eq 400
    end
  end

  describe 'POST /pm_webhook' do
    it 'logs a Postmark bounce' do
      post_json '/pm_webhook', { RecordType: 'Bounce', Email: 'ada@example.com', Type: 'HardBounce' }

      expect(WebhookLog.last).to have_attributes(service: 'postmark', event: 'Bounce', email: 'ada@example.com')
    end

    it 'logs delivery events, which name the address "Recipient"' do
      post_json '/pm_webhook', { RecordType: 'Delivery', Recipient: 'ada@example.com', MessageID: 'm-1' }

      expect(WebhookLog.last).to have_attributes(event: 'Delivery', email: 'ada@example.com')
    end
  end

  context 'when webhook credentials are configured' do
    around do |example|
      ENV['WEBHOOK_USERNAME'] = 'hooks'
      ENV['WEBHOOK_PASSWORD'] = 'test-only-password'
      example.run
    ensure
      ENV.delete('WEBHOOK_USERNAME')
      ENV.delete('WEBHOOK_PASSWORD')
    end

    it 'rejects calls without basic auth' do
      post_json '/pm_webhook', { RecordType: 'Bounce', Email: 'ada@example.com' }

      expect(last_response.status).to eq 401
      expect(WebhookLog.count).to eq 0
    end

    it 'accepts calls with the right credentials' do
      basic_authorize 'hooks', 'test-only-password'
      post_json '/pm_webhook', { RecordType: 'Bounce', Email: 'ada@example.com' }

      expect(last_response.status).to eq 200
      expect(WebhookLog.count).to eq 1
    end
  end
end

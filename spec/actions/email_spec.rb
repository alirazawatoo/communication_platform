require 'spec_helper'

RSpec.describe 'POST /email' do
  include Rack::Test::Methods

  def app
    CommunicationApp
  end

  let(:email_params) do
    {
      to: 'ada@example.com', to_name: 'Ada Lovelace',
      from: 'sender@example.com', from_name: 'Relay Demo',
      subject: 'Hello', body: '<p>Hi Ada</p>'
    }
  end

  def json_response
    JSON.parse(last_response.body)
  end

  it 'returns 422 with validation details when attributes are missing' do
    post '/email'
    expect(json_response['status']).to eq 422
    expect(json_response['message'].keys).to include('to', 'subject')
  end

  it 'sends through SendGrid first and stores the result' do
    stub_sendgrid
    post '/email', email_params

    expect(json_response).to include('status' => 202, 'message' => 'Success')
    expect(Email.last).to have_attributes(service: 'sendgrid', status: 202, to: 'ada@example.com')
    expect(WebMock).to have_requested(:post, ProviderStubs::SENDGRID_URL)
      .with(headers: { 'Authorization' => 'Bearer test-sendgrid-key' })
  end

  it 'falls back to Postmark when SendGrid rejects the request' do
    stub_sendgrid(status: 500, body: '{"errors":[]}')
    stub_postmark
    post '/email', email_params

    expect(json_response['status']).to eq 200
    expect(Email.last).to be_postmark
    expect(WebMock).to have_requested(:post, ProviderStubs::POSTMARK_URL)
      .with(headers: { 'X-Postmark-Server-Token' => 'test-postmark-token' })
  end

  it 'reports an error and stores nothing when every provider fails' do
    stub_sendgrid(status: 503)
    stub_postmark(status: 500)
    post '/email', email_params

    expect(json_response['status']).to eq 500
    expect(Email.count).to eq 0
  end

  it 'schedules through SendGrid only when send_at is given' do
    stub_sendgrid
    post '/email', email_params.merge(send_at: '2030-01-15T09:30:00+00:00')

    expect(Email.last.send_at).to eq Time.utc(2030, 1, 15, 9, 30)
    expect(WebMock).to have_requested(:post, ProviderStubs::SENDGRID_URL)
      .with { |request| JSON.parse(request.body)['send_at'] == Time.utc(2030, 1, 15, 9, 30).to_i }
    expect(WebMock).not_to have_requested(:post, ProviderStubs::POSTMARK_URL)
  end
end

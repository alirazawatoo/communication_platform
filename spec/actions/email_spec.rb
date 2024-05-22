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
    expect(last_response.status).to eq 422
    expect(json_response['status']).to eq 422
    expect(json_response['message'].keys).to include('to', 'subject')
  end

  it 'sends through SendGrid first and stores the result' do
    stub_sendgrid
    post '/email', email_params

    expect(last_response.status).to eq 201
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

  it 'answers 503 and stores nothing when every provider fails' do
    stub_sendgrid(status: 503)
    stub_postmark(status: 500)
    post '/email', email_params

    expect(last_response.status).to eq 503
    expect(json_response).to eq('status' => 503, 'message' => 'Email services are down or configured incorrectly')
    expect(Email.count).to eq 0
  end

  it 'falls back to Postmark when SendGrid cannot be reached' do
    stub_request(:post, ProviderStubs::SENDGRID_URL).to_timeout
    stub_postmark
    post '/email', email_params

    expect(last_response.status).to eq 201
    expect(Email.last).to be_postmark
  end

  it 'skips SendGrid when no API key is configured' do
    stub_postmark
    ENV['SG_KEY'] = ''
    post '/email', email_params

    expect(Email.last).to be_postmark
    expect(WebMock).not_to have_requested(:post, ProviderStubs::SENDGRID_URL)
  ensure
    ENV['SG_KEY'] = 'test-sendgrid-key'
  end

  it 'accepts a JSON body' do
    stub_sendgrid
    post '/email', email_params.to_json, 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq 201
    expect(json_response).to include('status' => 202, 'service' => 'sendgrid', 'id' => Email.last.id)
  end

  it 'answers 400 for malformed JSON' do
    post '/email', '{"to":', 'CONTENT_TYPE' => 'application/json'

    expect(last_response.status).to eq 400
    expect(json_response['message']).to eq 'Malformed JSON body'
  end

  it 'rejects attributes the client must not set, such as service or status' do
    post '/email', email_params.merge(service: 'postmark', status: 200)

    expect(last_response.status).to eq 422
    expect(json_response['message'].keys).to contain_exactly('service', 'status')
    expect(WebMock).not_to have_requested(:post, ProviderStubs::SENDGRID_URL)
  end

  it 'accepts send_at in the documented "DD MM YYYY HH:MM:SS +HH:MM" format' do
    stub_sendgrid
    post '/email', email_params.merge(send_at: '23 09 2030 18:17:06 -05:00')

    expect(Email.last.send_at).to eq Time.utc(2030, 9, 23, 23, 17, 6)
  end

  it 'answers 422 for a send_at it cannot read' do
    post '/email', email_params.merge(send_at: 'next tuesday-ish')

    expect(last_response.status).to eq 422
    expect(json_response['message']).to have_key('send_at')
  end

  it 'hides internal error details from the client' do
    allow(Email).to receive(:new).and_raise(RuntimeError, 'connection string with secrets')
    post '/email', email_params

    expect(last_response.status).to eq 500
    expect(json_response['message']).to eq 'Internal server error'
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

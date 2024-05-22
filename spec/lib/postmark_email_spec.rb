require 'spec_helper'

RSpec.describe EmailServices::PostmarkEmail do
  let(:meta) do
    { 'to' => 'jane@example.com', 'to_name' => 'Doe, Jane', 'from' => 'relay@example.com',
      'from_name' => 'Relay "Bot"', 'subject' => 'Hi', 'body' => '<p>Hi</p>', 'send_at' => nil }
  end

  it 'quotes display names so a comma does not split the recipient' do
    stub_postmark
    described_class.new.send_email(meta)

    expect(WebMock).to have_requested(:post, ProviderStubs::POSTMARK_URL).with { |request|
      body = JSON.parse(request.body)
      body['To'] == '"Doe, Jane" <jane@example.com>' && body['From'] == '"Relay Bot" <relay@example.com>'
    }
  end

  it 'leaves scheduled emails to SendGrid' do
    expect(described_class.new.send_email(meta.merge('send_at' => Time.now))).to be_nil
    expect(WebMock).not_to have_requested(:post, ProviderStubs::POSTMARK_URL)
  end
end

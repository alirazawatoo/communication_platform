require 'spec_helper'

RSpec.describe Email do
  describe 'validations' do
    it 'is valid with all required attributes' do
      expect(build(:email)).to be_valid
    end

    it 'requires the recipient, sender, subject and body' do
      email = Email.new
      expect(email).not_to be_valid
      expect(email.errors.to_hash.keys).to include(:to, :to_name, :from, :from_name, :subject, :body)
    end

    it 'rejects malformed addresses' do
      email = build(:email, to: 'not-an-address', from: 'also wrong')
      expect(email).not_to be_valid
      expect(email.errors.to_hash.keys).to include(:to, :from)
    end
  end

  describe 'service enum' do
    it 'records SendGrid as the service' do
      expect(build(:email, :sendgrid)).to be_sendgrid
    end

    it 'records Postmark as the service' do
      expect(build(:email, :postmark)).to be_postmark
    end
  end
end

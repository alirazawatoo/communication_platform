module EmailServices
  class SendgridEmail
    include HttpClient

    def self.api_url
      ENV.fetch('SENDGRID_API_URL', 'https://api.sendgrid.com/v3/mail/send')
    end

    def send_email(meta)
      return nil if ENV['SG_KEY'].to_s.empty?

      payload = {
        'personalizations' => [{ 'to' => [{ 'email' => meta['to'], 'name' => meta['to_name'] }] }],
        'from' => { 'email' => meta['from'], 'name' => meta['from_name'] },
        'subject' => meta['subject'],
        'content' => [{ 'type' => 'text/html', 'value' => meta['body'] }]
      }
      payload['send_at'] = meta['send_at'].to_i if meta['send_at'].present?

      post_json(self.class.api_url, payload, 'Authorization' => "Bearer #{ENV['SG_KEY']}")
    end
  end
end

module EmailServices
  class PostmarkEmail
    include HttpClient

    def self.api_url
      ENV.fetch('POSTMARK_API_URL', 'https://api.postmarkapp.com/email')
    end

    def send_email(meta)
      # Postmark has no scheduled sending, so scheduled emails stay with SendGrid.
      return nil if meta['send_at'].present?
      return nil if ENV['POSTMARK_TOKEN'].to_s.empty?

      payload = {
        'From' => mailbox(meta['from_name'], meta['from']),
        'To' => mailbox(meta['to_name'], meta['to']),
        'Subject' => meta['subject'],
        'HtmlBody' => meta['body']
      }
      headers = { 'Accept' => 'application/json', 'X-Postmark-Server-Token' => ENV['POSTMARK_TOKEN'] }

      post_json(self.class.api_url, payload, headers)
    end

    private

    # Quote the display name so commas ("Doe, Jane") don't split it into two recipients.
    def mailbox(name, address)
      %("#{name.to_s.delete('"\\')}" <#{address}>)
    end
  end
end

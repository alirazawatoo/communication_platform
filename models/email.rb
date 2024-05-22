class Email < ActiveRecord::Base
  class DeliveryFailed < StandardError
    def initialize(message = 'Email services are down or configured incorrectly')
      super
    end
  end

  REQUEST_ATTRIBUTES = %w[to to_name from from_name subject body send_at].freeze
  # Format documented in the README, e.g. "23 09 2019 18:17:06 -05:00".
  SEND_AT_FORMAT = '%d %m %Y %H:%M:%S %z'.freeze

  # Providers in order of preference; the first one that accepts the email wins.
  DELIVERY_SERVICES = {
    sendgrid: EmailServices::SendgridEmail,
    postmark: EmailServices::PostmarkEmail
  }.freeze

  enum :service, { postmark: 0, sendgrid: 1 }

  validates :to, :from, :subject, :body, :to_name, :from_name, presence: true
  validates :to, :from, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :send_at_parseable

  def send_at=(value)
    @raw_send_at = value
    super(value.is_a?(String) ? parse_send_at(value) : value)
  end

  # Sends through the first provider that accepts the request, then stores the email.
  # Returns false when the email is invalid; raises DeliveryFailed when every provider fails.
  def deliver
    return false unless valid?

    DELIVERY_SERVICES.each do |service_name, client|
      response = client.new.send_email(attributes)
      next unless response.is_a?(Net::HTTPSuccess)

      assign_attributes(service: service_name, status: response.code.to_i, api_response: parse_body(response.body))
      return save!
    end

    raise DeliveryFailed
  end

  private

  def parse_send_at(value)
    return nil if value.strip.empty?

    DateTime.strptime(value.strip, SEND_AT_FORMAT)
  rescue Date::Error
    begin
      DateTime.iso8601(value.strip)
    rescue Date::Error
      nil
    end
  end

  def send_at_parseable
    return if @raw_send_at.blank? || send_at.present?

    errors.add(:send_at, :invalid, message: "must look like \"23 09 2019 18:17:06 -05:00\" or ISO 8601")
  end

  def parse_body(body)
    return nil if body.blank?

    JSON.parse(body)
  rescue JSON::ParserError
    body
  end
end

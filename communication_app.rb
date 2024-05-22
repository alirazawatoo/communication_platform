class CommunicationApp < Sinatra::Base
  set :show_exceptions, false
  # Unexpected errors always go through the JSON error handler, in specs as in production.
  set :raise_errors, false

  configure(:development, :production) { enable :logging }

  before { content_type :json }

  post '/email' do
    attributes = request_payload
    halt 400, json_message(400, 'Request body must be a JSON object') unless attributes.is_a?(Hash)

    unknown = attributes.keys - Email::REQUEST_ATTRIBUTES
    halt 422, json_message(422, unknown.to_h { |key| [key, [{ error: :unknown_attribute }]] }) if unknown.any?

    email = Email.new(attributes)
    if email.deliver
      status 201
      { status: email.status, message: 'Success', id: email.id, service: email.service }.to_json
    else
      json_message(422, email.errors.details)
    end
  rescue Email::DeliveryFailed => e
    json_message(503, e.message)
  end

  post '/sg_webhook' do
    require_webhook_credentials!
    events = request_payload
    halt 400, json_message(400, 'Expected a JSON array of events') unless events.is_a?(Array)

    logged = events.count do |event|
      event.is_a?(Hash) &&
        WebhookLog.create(service: :sendgrid, event: event['event'], email: event['email'], response: event).persisted?
    end
    { status: 200, logged: logged }.to_json
  end

  post '/pm_webhook' do
    require_webhook_credentials!
    payload = request_payload
    halt 400, json_message(400, 'Expected a JSON object') unless payload.is_a?(Hash)

    # Bounce and SpamComplaint events carry "Email"; Delivery, Open and Click carry "Recipient".
    log = WebhookLog.create(service: :postmark, event: payload['RecordType'],
                            email: payload['Email'] || payload['Recipient'], response: payload)
    { status: 200, logged: log.persisted? ? 1 : 0 }.to_json
  end

  error do
    json_message(500, 'Internal server error')
  end

  private

  def json_message(code, message)
    status code
    { status: code, message: message }.to_json
  end

  def request_payload
    return params.to_h unless request.media_type == 'application/json'

    JSON.parse(request.body.read)
  rescue JSON::ParserError
    halt 400, json_message(400, 'Malformed JSON body')
  end

  # Both providers can call a webhook URL with HTTP basic auth; enforce it once credentials are configured.
  def require_webhook_credentials!
    username = ENV['WEBHOOK_USERNAME'].to_s
    password = ENV['WEBHOOK_PASSWORD'].to_s
    return if username.empty? || password.empty?

    auth = Rack::Auth::Basic::Request.new(request.env)
    given_user, given_password = auth.provided? && auth.basic? ? auth.credentials : ['', '']
    authorized = Rack::Utils.secure_compare(given_user, username) & Rack::Utils.secure_compare(given_password, password)
    return if authorized

    headers 'WWW-Authenticate' => 'Basic realm="webhooks"'
    halt 401, json_message(401, 'Unauthorized')
  end
end

class CommunicationApp < Sinatra::Base
  set :show_exceptions, false
  
  post "/email" do
    attributes = email_attributes
    email = Email.new(attributes)

    if email.save
      email = email.reload

      status = email.status
      message = 'Success'
      
    elsif email.errors.any?
      status = 422
      message = email.errors.details

    else
      status = 500
      message = 'Internal server error'

    end

    { status: status, message: message }.to_json
  end

  post '/sg_webhook' do
    params = JSON.parse(request.body.read)
    WebhookLog.create(service: :sendgrid, event: params[0]['event'], email: params[0]['email'], response: params)
  end

  post '/pm_webhook' do
    params = JSON.parse(request.body.read)
    WebhookLog.create(service: :postmark, event: params['RecordType'], email: params['Email'], response: params)
  end 

  error do
    { status: 500, message: env['sinatra.error'].message }.to_json 
  end 

  private

  # rack-parser used to turn JSON bodies into params in config.ru; parse them here so specs cover it too.
  def email_attributes
    attributes = request.media_type == 'application/json' ? JSON.parse(request.body.read) : params.to_h
    attributes['send_at'] = DateTime.parse(attributes['send_at']) if attributes['send_at'].present?
    attributes
  end
end

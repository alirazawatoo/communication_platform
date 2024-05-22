module EmailServices
  # Shared POST helper: bounded timeouts, and network failures return nil so the next provider gets a turn.
  module HttpClient
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
    ].freeze

    def post_json(url, payload, headers)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 15) do |http|
        http.post(uri.request_uri, payload.to_json, headers.merge('Content-Type' => 'application/json'))
      end
    rescue *NETWORK_ERRORS => e
      warn "#{self.class.name}: #{e.class}: #{e.message}"
      nil
    end
  end
end

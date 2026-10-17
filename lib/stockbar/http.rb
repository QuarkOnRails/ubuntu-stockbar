# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module Stockbar
  class HTTP
    def get_json(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                     open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      raise HTTPError, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise HTTPError, "invalid response"
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError,
           Net::HTTPBadResponse, EOFError => e
      raise HTTPError, "#{uri.host} unreachable (#{e.message})"
    end
  end
end

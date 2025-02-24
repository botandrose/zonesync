require "net/http"
require "json"

module Zonesync
  class HTTP < Struct.new(:base)
    def initialize(...)
      super 
      @before_request = []
      @after_response = []
    end

    def get path
      request("get", path)
    end

    def post path, body
      request("post", path, body)
    end

    def patch path, body
      request("patch", path, body)
    end

    def delete path
      request("delete", path)
    end

    def before_request &block
      @before_request << block
    end

    def after_response &block
      @after_response << block
    end

    def request method, path, body=nil
      uri = URI.parse("#{base}#{path}")
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri.path)

      @before_request.each do |block|
        block.call(request, uri, body)
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        body = JSON.dump(body) if request.fetch("Content-Type", "").include?("application/json")
        http.request(request, body)
      end

      @after_response.each do |block|
        call(response)
      end

      raise response.body unless response.code =~ /^20.$/
      if response["Content-Type"].include?("application/json")
        JSON.parse(response.body)
      else
        response.body
      end
    end
  end
end

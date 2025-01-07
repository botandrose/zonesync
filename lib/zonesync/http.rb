# typed: strict
require "sorbet-runtime"

require "net/http"
require "json"

module Zonesync
  HTTP = Struct.new(:base) do
    extend T::Sig

    sig { params(base: String).void }
    def initialize(base)
      super
      @before_request = T.let([], T::Array[T.untyped])
      @after_response = T.let([], T::Array[T.untyped])
    end

    sig { params(path: String).returns(T.untyped) }
    def get path
      request("get", path)
    end

    sig { params(path: String, body: T.untyped).returns(T.untyped) }
    def post path, body
      request("post", path, body)
    end

    sig { params(path: String, body: T.untyped).returns(T.untyped) }
    def patch path, body
      request("patch", path, body)
    end

    sig { params(path: String).returns(T.untyped) }
    def delete path
      request("delete", path)
    end

    sig { params(block: T.proc.params(arg0: T.untyped, arg1: T.untyped, arg2: T.untyped).void).void }
    def before_request &block
      @before_request << block
    end

    sig { params(block: T.proc.params(arg0: T.untyped).void).void }
    def after_response &block
      @after_response << block
    end

    sig { params(method: String, path: String, body: T.untyped).returns(T.untyped) }
    def request method, path, body=nil
      uri = URI.parse("#{base}#{path}")
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri.path)

      @before_request.each do |block|
        block.call(request, uri, body)
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        if request.fetch("Content-Type", "").include?("application/json")
          http.request(request, JSON.dump(body))
        else
          http.request(request, body)
        end
      end

      @after_response.each do |block|
        block.call(response)
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

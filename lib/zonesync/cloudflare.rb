require "net/http"

module Zonesync
  class Cloudflare < Provider
    def read
      get("/export")
    end

    def remove record
      id = records.fetch(record)
      delete("/#{id}")
    end

    def change old_record, new_record
      id = records.fetch(old_record)
      patch("/#{id}", {
        name: new_record[:name],
        type: new_record[:type],
        ttl: new_record[:ttl],
        content: new_record[:rdata],
      })
    end

    def add record
      post(nil, {
        name: record[:name],
        type: record[:type],
        ttl: record[:ttl],
        content: record[:rdata],
      })
    end

    def records
      @records ||= begin
        response = get(nil)
        response["result"].reduce({}) do |map, attrs|
          map.merge attrs["id"] => Record.new(
            attrs["name"],
            attrs["type"],
            attrs["ttl"].to_i,
            attrs["content"],
          ).to_h
        end.invert
      end
    end

    private

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

    def request method, path, body=nil
      uri = URI.join("https://api.cloudflare.com/client/v4/zones/#{credentials[:zone_id]}/dns_records#{path}")
      request = Net::HTTP.const_get(method.to_s.capitalize).new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-Auth-Email"] = credentials[:email]
      request["X-Auth-Key"] = credentials[:key]

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        data = body ? JSON.dump(body) : nil
        http.request(request, data)
      end
      raise response.body unless response.code == "200"
      if response["Content-Type"].include?("application/json")
        JSON.parse(response.body)
      else
        response.body
      end
    end
  end
end


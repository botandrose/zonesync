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
        content: new_record[:address],
        name: new_record[:host],
        type: new_record[:type],
        ttl: new_record[:ttl],
      })
    end

    def add record
      post(nil, {
        content: record[:address],
        name: record[:host],
        type: record[:type],
        ttl: record[:ttl],
      })
    end

    def records
      @records ||= Records.load(get(nil))
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

      result = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        data = body ? JSON.dump(body) : nil
        http.request(request, data)
      end
      result.body
    end

    class Records
      def self.load json
        JSON.parse(json)["result"].reduce({}) do |map, attrs|
          map.merge attrs["id"] => {
            type: attrs["type"],
            host: attrs["name"],
            ttl: attrs["ttl"].to_i,
            address: attrs["content"],
          }
        end.invert
      end
    end
  end
end


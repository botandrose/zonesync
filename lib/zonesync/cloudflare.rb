require "zonesync/record"
require "zonesync/http"

module Zonesync
  class Cloudflare < Provider
    def read
      http.get("/export")
    end

    def remove record
      id = records.fetch(record)
      http.delete("/#{id}")
    end

    def change old_record, new_record
      id = records.fetch(old_record)
      http.patch("/#{id}", {
        name: new_record[:name],
        type: new_record[:type],
        ttl: new_record[:ttl],
        content: new_record[:rdata],
      })
    end

    def add record
      http.post(nil, {
        name: record[:name],
        type: record[:type],
        ttl: record[:ttl],
        content: record[:rdata],
      })
    end

    def records
      @records ||= begin
        response = http.get(nil)
        response["result"].reduce({}) do |map, attrs|
          map.merge attrs["id"] => Record.new(
            attrs["name"] + ".", # normalize to trailing period
            attrs["type"],
            attrs["ttl"].to_i,
            attrs["content"],
          ).to_h
        end.invert
      end
    end

    private

    def http
      return @http if @http
      @http = HTTP.new("https://api.cloudflare.com/client/v4/zones/#{credentials[:zone_id]}/dns_records")
      @http.before_request do |request|
        request["Content-Type"] = "application/json"
        request["X-Auth-Email"] = credentials[:email]
        request["X-Auth-Key"] = credentials[:key]
      end
      @http.after_response do |response|
      end
      @http
    end
  end
end


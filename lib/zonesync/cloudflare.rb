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
          map.merge to_record(attrs) => attrs["id"]
        end
      end
    end

    private

    def to_record attrs
      rdata = attrs["content"]
      if %w[CNAME MX].include?(attrs["type"])
        rdata = normalize_trailing_period(rdata)
      end
      if %w[TXT SPF NAPTR].include?(attrs["type"])
        rdata = normalize_quoting(rdata)
      end
      Record.new(
        normalize_trailing_period(attrs["name"]),
        attrs["type"],
        attrs["ttl"].to_i,
        rdata,
      ).to_h
    end

    def normalize_trailing_period value
      value =~ /\.$/ ? value : value + "."
    end

    def normalize_quoting value
      value =~ /^".+"$/ ? value : %("#{value}")
    end

    def http
      return @http if @http
      @http = HTTP.new("https://api.cloudflare.com/client/v4/zones/#{credentials[:zone_id]}/dns_records")
      @http.before_request do |request|
        request["Content-Type"] = "application/json"
        if credentials[:token]
          request["Authorization"] = "Bearer #{credentials[:token]}"
        else
          request["X-Auth-Email"] = credentials[:email]
          request["X-Auth-Key"] = credentials[:key]
        end
      end
      @http
    end
  end
end


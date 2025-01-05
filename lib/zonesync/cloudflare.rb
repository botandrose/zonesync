require "zonesync/record"
require "zonesync/http"

module Zonesync
  class Cloudflare < Provider
    def read
      ([fake_soa] + all.keys.map do |hash|
        Record.new(hash)
      end).map(&:to_s).join("\n") + "\n"
    end

    def remove record
      id = all.fetch(record.to_h)
      http.delete("/#{id}")
    end

    def change old_record, new_record
      id = all.fetch(old_record.to_h)
      http.patch("/#{id}", {
        name: new_record[:name],
        type: new_record[:type],
        ttl: new_record[:ttl],
        content: new_record[:rdata],
        comment: new_record[:comment],
      })
    end

    def add record
      http.post(nil, {
        name: record[:name],
        type: record[:type],
        ttl: record[:ttl],
        content: record[:rdata],
        comment: record[:comment],
      })
    end

    def all
      @all ||= begin
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
        name: normalize_trailing_period(attrs["name"]),
        type: attrs["type"],
        ttl: attrs["ttl"].to_i,
        rdata:,
        comment: attrs["comment"],
      ).to_h
    end

    def normalize_trailing_period value
      value =~ /\.$/ ? value : value + "."
    end

    def normalize_quoting value
      value =~ /^".+"$/ ? value : %("#{value}")
    end

    def fake_soa
      zone_name = http.get("/..")["result"]["name"]
      Record.new(
        name: normalize_trailing_period(zone_name),
        type: "SOA",
        ttl: 1,
        rdata: "#{zone_name} admin.#{zone_name} 2000010101 1 1 1 1",
        comment: nil,
      )
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


# typed: strict
require "sorbet-runtime"

require "zonesync/record"
require "zonesync/http"

module Zonesync
  class Cloudflare < Provider
    sig { returns(String) }
    def read
      records = [fake_soa] + all.keys
      records.map(&:to_s).join("\n") + "\n"
    end

    sig { params(record: Record).void }
    def remove record
      id = all.fetch(record)
      http.delete("/#{id}")
    end

    sig { params(old_record: Record, new_record: Record).void }
    def change old_record, new_record
      id = all.fetch(old_record)
      http.patch("/#{id}", to_hash(new_record))
    end

    sig { params(record: Record).void }
    def add record
      http.post("", to_hash(record))
    end

    sig { returns(T::Hash[Record, String]) }
    def all
      response = http.get("")
      response["result"].reduce({}) do |map, attrs|
        map.merge to_record(attrs) => attrs["id"]
      end
    end

    private

    sig { params(record: Record).returns(T::Hash[String, String]) }
    def to_hash record
      hash = record.to_h
      content = hash.delete(:rdata)

      if record.type == "MX"
        # For MX records, split "priority hostname" into separate fields
        priority, hostname = T.must(content).split(" ", 2)
        hash[:priority] = priority.to_i
        hash[:content] = hostname.sub(/\.$/, "") # remove trailing dot
      else
        hash[:content] = content
      end

      hash[:comment] = hash.delete(:comment) # maintain original order
      hash
    end

    sig { params(attrs: T::Hash[String, String]).returns(Record) }
    def to_record attrs
      rdata = attrs["content"]
      if %w[CNAME MX].include?(attrs["type"])
        rdata = normalize_trailing_period(T.must(rdata))
      end
      if attrs["type"] == "MX"
        rdata = "#{attrs["priority"]} #{rdata}"
      end
      if %w[TXT SPF NAPTR].include?(attrs["type"])
        rdata = normalize_quoting(T.must(rdata))
      end
      Record.new(
        name: normalize_trailing_period(T.must(attrs["name"])),
        type: attrs["type"],
        ttl: attrs["ttl"].to_i,
        rdata:,
        comment: attrs["comment"],
      )
    end

    sig { params(value: String).returns(String) }
    def normalize_trailing_period value
      value =~ /\.$/ ? value : value + "."
    end

    sig { params(value: String).returns(String) }
    def normalize_quoting value
      value = value =~ /^".+"$/ ? value : %("#{value}") # handle quote wrapping
      value.gsub('" "', "") # handle multiple txt record joining
    end

    sig { returns(Zonesync::Record) }
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

    sig { returns(HTTP) }
    def http
      return @http if @http
      @http = T.let(HTTP.new("https://api.cloudflare.com/client/v4/zones/#{config.fetch(:zone_id)}/dns_records"), T.nilable(Zonesync::HTTP))
      T.must(@http).before_request do |request|
        request["Content-Type"] = "application/json"
        if config[:token]
          request["Authorization"] = "Bearer #{config[:token]}"
        else
          request["X-Auth-Email"] = config.fetch(:email)
          request["X-Auth-Key"] = config.fetch(:key)
        end
      end
      T.must(@http)
    end
  end
end


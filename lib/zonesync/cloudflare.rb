# frozen_string_literal: true

require "zonesync/record"
require "zonesync/http"
require "zonesync/cloudflare/proxied_support"

module Zonesync
  class Cloudflare < Provider
    def read
      records = [fake_soa.extend(ProxiedSupport)] + all.keys
      records.map(&:to_s).join("\n") + "\n"
    end

    def diff(other)
      source_records = other.diffable_records.map { |r| r.extend(ProxiedSupport) }
      Diff.new(
        from: diffable_records,
        to: source_records,
      )
    end

    def remove(record)
      id = find_record_id(record)
      http.delete("/#{id}")
    end

    def change(old_record, new_record)
      id = find_record_id(old_record)
      http.patch("/#{id}", to_hash(new_record))
    end

    def find_record_id(record)
      all.each do |existing, id|
        return id if existing.identical_to?(record)
      end
      raise KeyError, "record not found: #{record.inspect}"
    end

    def add(record)
      add_with_duplicate_handling(record) do
        begin
          http.post("", to_hash(record))
        rescue RuntimeError => e
          # Convert CloudFlare-specific duplicate error to standard exception
          if e.message.include?('"code":81058') && e.message.include?("An identical record already exists")
            raise DuplicateRecordError.new(record, "CloudFlare error 81058")
          else
            # Re-raise other errors
            raise
          end
        end
      end
    end

    def all
      response = http.get("")
      response["result"].reduce({}) do |map, attrs|
        map.merge(to_record(attrs) => attrs["id"])
      end
    end

    private

    def to_hash(record)
      hash = record.to_h
      content = hash.delete(:rdata)
      proxied = hash.delete(:proxied)

      if record.type == "MX"
        # For MX records, split "priority hostname" into separate fields
        priority, hostname = content.split(" ", 2)
        hash[:priority] = priority.to_i
        hash[:content] = hostname.sub(/\.$/, "") # remove trailing dot
      else
        hash[:content] = content
      end

      hash[:proxied] = proxied if proxied != nil
      hash[:comment] = hash.delete(:comment) # maintain original order
      hash
    end

    def to_record(attrs)
      rdata = attrs["content"]
      if %w[CNAME MX].include?(attrs["type"])
        rdata = normalize_trailing_period(rdata)
      end
      if attrs["type"] == "MX"
        rdata = "#{attrs["priority"]} #{rdata}"
      end
      if %w[TXT SPF NAPTR].include?(attrs["type"])
        rdata = normalize_quoting(rdata)
      end

      record = Record.new(
        name: normalize_trailing_period(attrs["name"]),
        type: attrs["type"],
        ttl: attrs["ttl"].to_i,
        rdata: rdata,
        comment: comment_with_proxied(attrs["comment"], attrs["proxied"]),
      )
      record.extend(ProxiedSupport)
    end

    def comment_with_proxied(comment, proxied)
      return comment if proxied.nil?
      cf_tag = "cf_tags=cf-proxied:#{proxied}"
      [comment, cf_tag].compact.join(" ")
    end

    def normalize_trailing_period(value)
      value =~ /\.$/ ? value : value + "."
    end

    def normalize_quoting(value)
      value = value =~ /^".+"$/ ? value : %("#{value}") # handle quote wrapping
      value.gsub('" "', "") # handle multiple txt record joining
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
      @http = HTTP.new("https://api.cloudflare.com/client/v4/zones/#{config.fetch(:zone_id)}/dns_records")
      @http.before_request do |request|
        request["Content-Type"] = "application/json"
        if config[:token]
          request["Authorization"] = "Bearer #{config[:token]}"
        else
          request["X-Auth-Email"] = config.fetch(:email)
          request["X-Auth-Key"] = config.fetch(:key)
        end
      end
      @http
    end
  end
end

# frozen_string_literal: true

module Zonesync
  Record = Struct.new(:name, :type, :ttl, :rdata, :comment, keyword_init: true) do
    # Make Record immutable by removing setters
    undef_method :name=, :type=, :ttl=, :rdata=, :comment=, :[]=

    def self.from_dns_zonefile_record(record)
      new(
        name: record.host,
        type: record.type,
        ttl: record.ttl,
        rdata: record.rdata,
        comment: record.comment,
      )
    end

    def short_name(origin)
      ret = name.sub(origin, "")
      ret = ret.sub(/\.$/, "")
      ret = "@" if ret == ""
      ret
    end

    def manifest?
      type == "TXT" &&
        name.match?(/^zonesync_manifest\./)
    end

    def checksum?
      type == "TXT" &&
        name.match?(/^zonesync_checksum\./)
    end

    def <=>(other)
      to_sortable <=> other.to_sortable
    end

    def to_sortable
      is_soa = type == "SOA" ? 0 : 1
      [is_soa, type, name, rdata, ttl.to_i]
    end

    def to_s
      string = [name, ttl, type, rdata].join(" ")
      string << " ; #{comment}" if comment
      string
    end

    def identical_to?(other)
      name == other.name && type == other.type && ttl == other.ttl && rdata == other.rdata
    end

    def conflicts_with?(other)
      return false unless name == other.name && type == other.type

      case type
      when "CNAME", "SOA"
        true
      when "MX"
        existing_priority = rdata.split(' ').first
        new_priority = other.rdata.split(' ').first
        existing_priority == new_priority
      else
        false
      end
    end

    def self.single_record_per_name?(type)
      type == "CNAME" || type == "SOA"
    end

    def self.non_meta(records)
      records.reject { |r| r.manifest? || r.checksum? }
    end
  end
end

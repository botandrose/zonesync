# typed: strict
require "sorbet-runtime"

module Zonesync
  Record = Struct.new(:name, :type, :ttl, :rdata, :comment, keyword_init: true) do
    extend T::Sig

    sig { params(record: Zonesync::Parser::Record).returns(Record) }
    def self.from_dns_zonefile_record record
      new(
        name: record.host,
        type: record.type,
        ttl: record.ttl,
        rdata: record.rdata,
        comment: record.comment,
      )
    end

    sig { params(origin: String).returns(String) }
    def short_name origin
      ret = name.sub(origin, "")
      ret = ret.sub(/\.$/, "")
      ret = "@" if ret == ""
      ret
    end

    sig { returns(T::Boolean) }
    def manifest?
      type == "TXT" &&
        name.match?(/^zonesync_manifest\./)
    end

    sig { returns(T::Boolean) }
    def checksum?
      type == "TXT" &&
        name.match?(/^zonesync_checksum\./)
    end

    sig { params(other: Record).returns(Integer) }
    def <=> other
      to_sortable <=> other.to_sortable
    end

    sig { returns([Integer, String, String, String, Integer]) }
    def to_sortable
      is_soa = type == "SOA" ? 0 : 1
      [is_soa, type, name, rdata, ttl.to_i]
    end

    sig { returns(String) }
    def to_s
      string = [name, ttl, type, rdata].join(" ")
      string << " ; #{comment}" if comment
      string
    end

    sig { params(other: Record).returns(T::Boolean) }
    def identical_to?(other)
      name == other.name && type == other.type && ttl == other.ttl && rdata == other.rdata
    end

    sig { params(other: Record).returns(T::Boolean) }
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

    sig { params(type: String).returns(T::Boolean) }
    def self.single_record_per_name?(type)
      type == "CNAME" || type == "SOA"
    end

    sig { params(records: T::Array[Record]).returns(T::Array[Record]) }
    def self.non_meta(records)
      records.reject { |r| r.manifest? || r.checksum? }
    end
  end
end


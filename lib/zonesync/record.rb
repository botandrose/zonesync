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
  end
end


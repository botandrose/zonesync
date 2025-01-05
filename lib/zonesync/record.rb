module Zonesync
  class Record < Struct.new(:name, :type, :ttl, :rdata, :comment, keyword_init: true)
    def self.from_dns_zonefile_record record
      type = record.class.name.split("::").last
      rdata = case type
      when "SOA"
        def record.host = origin
        "" # it just gets ignored anyways
      when "A", "AAAA"
        record.address
      when "CNAME", "NS", "PTR"
        record.domainname
      when "MX"
        "#{record.priority} #{record.domainname}"
      when "TXT", "SPF", "NAPTR"
        record.data
      else
        raise NotImplementedError.new(record.class).to_s
      end

      new(
        name: record.host,
        type:,
        ttl: record.ttl,
        rdata:,
        comment: record.comment,
      )
    end

    def short_name origin
      ret = name.sub(origin, "")
      ret = ret.sub(/\.$/, "")
      ret = "@" if ret == ""
      ret
    end

    def manifest?
      type == "TXT" &&
        name =~ /^zonesync_manifest\./
    end

    def checksum?
      type == "TXT" &&
        name =~ /^zonesync_checksum\./
    end

    def <=> other
      to_sortable <=> other.to_sortable
    end

    def to_sortable
      is_soa = type == "SOA" ? 0 : 1
      [is_soa, type, name, rdata, ttl]
    end

    def to_s
      string = [name, ttl, type, rdata].join(" ")
      string << " ; #{comment}" if comment
      string
    end
  end
end


module Zonesync
  class Record < Struct.new(:name, :type, :ttl, :rdata)
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
        record.host,
        type,
        record.ttl,
        rdata,
      )
    end
  end
end


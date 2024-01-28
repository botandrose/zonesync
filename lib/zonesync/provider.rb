require "dns/zonefile"
require "zonesync/record"

module Zonesync
  class Provider < Struct.new(:credentials)
    def self.from credentials
      Zonesync.const_get(credentials[:provider]).new(credentials)
    end

    def diffable_records
      DNS::Zonefile.load(read).records.map do |record|
        rdata = case record
        when DNS::Zonefile::A, DNS::Zonefile::AAAA
          record.address
        when DNS::Zonefile::CNAME
          record.domainname
        when DNS::Zonefile::MX
          record.domainname
        when DNS::Zonefile::TXT
          record.data
        else
          next
        end
        Record.new(
          record.host,
          record.class.name.split("::").last,
          record.ttl,
          rdata,
        )
      end.compact
    end

    def read record
      raise NotImplementedError
    end

    def remove record
      raise NotImplementedError
    end

    def change old_record, new_record
      raise NotImplementedError
    end

    def add record
      raise NotImplementedError
    end
  end

  require "zonesync/cloudflare"

  class Memory < Provider
    def read
      credentials[:string]
    end
  end

  class Filesystem < Provider
    def read
      File.read(credentials[:path])
    end
  end
end


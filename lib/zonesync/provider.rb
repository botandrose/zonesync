require "dns/zonefile"
require "zonesync/record"

module Zonesync
  class Provider < Struct.new(:credentials)
    def zonefile
      @adapter = Zonesync.const_get(credentials[:provider]).new(credentials)
      DNS::Zonefile.load(@adapter.read)
    end

    %i[read remove change add].each do |method|
      define_method method do |*args|
        @adapter.send(method, *args)
      end
    end

    def diffable_records
      zonefile.records.map do |record|
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
  end

  require "zonesync/cloudflare"

  class Memory < Provider
    def read
      credentials[:string]
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

  class Filesystem < Provider
    def read
      File.read(credentials[:path])
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
end


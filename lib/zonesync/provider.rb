require "dns/zonefile"

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
      diffable_record_types = [
        DNS::Zonefile::A,
        DNS::Zonefile::AAAA,
        DNS::Zonefile::CNAME,
        DNS::Zonefile::MX,
        DNS::Zonefile::TXT,
      ]
      zonefile.records.select do |record|
        diffable_record_types.include?(record.class)
      end
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


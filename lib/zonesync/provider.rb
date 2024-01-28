require "dns/zonefile"
require "zonesync/record"

module Zonesync
  class Provider < Struct.new(:credentials)
    def self.from credentials
      Zonesync.const_get(credentials[:provider]).new(credentials)
    end

    def diffable_records
      DNS::Zonefile.load(read).records.map do |record|
        Record.from_dns_zonefile_record(record)
      end.select do |record|
        %w[A AAAA CNAME MX TXT SPF NAPTR PTR].include?(record.type)
      end.sort
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


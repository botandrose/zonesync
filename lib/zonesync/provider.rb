require "zonesync/record"
require "zonesync/zonefile"

module Zonesync
  class Provider < Struct.new(:credentials)
    def self.from credentials
      return credentials if credentials.is_a?(Provider)
      Zonesync.const_get(credentials[:provider]).new(credentials)
    end

    def diffable_records
      zonefile.records.map do |record|
        Record.from_dns_zonefile_record(record)
      end.select do |record|
        %w[A AAAA CNAME MX TXT SPF NAPTR PTR].include?(record.type)
      end.reject do |record|
        record.comment.to_s.downcase.include? "zonesync: ignore"
      end.sort
    end

    private def zonefile
      body = read
      if body !~ /\sSOA\s/ # insert dummy SOA to trick parser if needed
        body.sub!(/\n([^$])/, "\n@ 1 SOA example.com example.com ( 2000010101 1 1 1 1 )\n\\1")
      end
      Zonefile.load(body)
    end

    def read record
      raise NotImplementedError
    end

    def write text
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
  require "zonesync/route53"

  class Memory < Provider
    def read
      credentials[:string]
    end

    def write string
      credentials[:string] = string
    end
  end

  class Filesystem < Provider
    def read
      File.read(credentials[:path])
    end

    def write string
      File.write(credentials[:path], string)
    end
  end
end


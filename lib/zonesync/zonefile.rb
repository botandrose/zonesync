# frozen_string_literal: true

require "zonesync/parser"

module Zonesync
  class Zonefile
    def self.load(zone_string)
      if zone_string !~ /\sSOA\s/ # insert dummy SOA to trick parser if needed
        zone_string.sub!(/\n([^$])/, "\n@ 1 SOA example.com example.com ( 2000010101 1 1 1 1 )\n\\1")
      end
      zone = Parser.parse(zone_string)
      records = zone.records.map do |dns_zonefile_record|
        Zonesync::Record.from_dns_zonefile_record(dns_zonefile_record)
      end
      new(records, origin: zone.origin)
    end

    def initialize(records, origin:)
      @records = records
      @origin = origin
    end

    attr_reader :records
    attr_reader :origin
  end
end

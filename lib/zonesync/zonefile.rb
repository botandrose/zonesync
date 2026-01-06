# frozen_string_literal: true

require "zonesync/parser"

module Zonesync
  class Zonefile
    DUMMY_SOA = "@ 1 SOA example.com example.com ( 2000010101 1 1 1 1 )\n"

    # Inserts a dummy SOA record if needed for parsing.
    # Returns [modified_content, insertion_offset] where insertion_offset is nil if no SOA was added,
    # or the byte position and length of the inserted SOA.
    def self.ensure_soa(zone_string)
      if zone_string =~ /\sSOA\s/
        [zone_string, nil]
      else
        content = zone_string.dup
        match = content.match(/\n([^$])/)
        if match
          insertion_point = match.begin(0) + 1
          content.sub!(/\n([^$])/, "\n#{DUMMY_SOA}\\1")
          [content, { at: insertion_point, length: DUMMY_SOA.length }]
        else
          [content, nil]
        end
      end
    end

    def self.load(zone_string)
      content, _ = ensure_soa(zone_string)
      zone = Parser.parse(content)
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

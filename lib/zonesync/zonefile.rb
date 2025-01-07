# typed: strict
require "sorbet-runtime"

require "zonesync/parser"

module Zonesync
  class Zonefile
    extend T::Sig

    sig { params(zone_string: String).returns(Zonefile) }
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

    sig { params(records: T::Array[Zonesync::Record], origin: String).void }
    def initialize records, origin:
      @records = records
      @origin = origin
    end

    sig { returns(T::Array[Zonesync::Record]) }
    attr_reader :records

    sig { returns(String) }
    attr_reader :origin
  end
end

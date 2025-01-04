require "zonesync/record"
require "json"

module Zonesync
  class Manifest < Struct.new(:diffable_records, :zone)
    def self.generate diffable_records, zone
      new(diffable_records, zone).generate
    end

    def self.diffable_record_types
      %w[A AAAA CNAME MX TXT SPF NAPTR PTR].sort
    end

    def self.diffable? record
      diffable_record_types.include?(record.type) &&
        record.name !~ /^zonesync_manifest/
    end

    def generate
      Record.new(
        "zonesync_manifest.#{zone.origin}",
        "TXT",
        zone.default_ttl || 3600,
        rdata,
        nil,
      )
    end

    private

    def rdata
      JSON.dump(manifest)
        .gsub(/"(\w+)":/, '\1:')
        .gsub('"', "'")
        .gsub('],', "], ")
        .inspect
    end

    def manifest
      diffable_records.reduce({}) do |hash, record|
        next hash unless self.class.diffable?(record)
        hash[record.type] ||= []
        hash[record.type] << record.short_name(zone.origin)
        hash[record.type].sort!
        hash
      end
    end
  end
end

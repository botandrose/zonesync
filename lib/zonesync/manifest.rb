require "zonesync/record"
require "json"

module Zonesync
  class Manifest < Struct.new(:records, :zone)
    DIFFABLE_RECORD_TYPES =
      %w[A AAAA CNAME MX TXT SPF NAPTR PTR].sort

    def existing
      records.find(&:manifest?)
    end

    def existing?
      !!existing
    end

    def generate
      Record.new(
        "zonesync_manifest.#{zone.origin}",
        "TXT",
        zone.default_ttl || 3600,
        generate_rdata,
        nil,
      )
    end

    def diffable? record
      if existing?
        matches?(record)
      else
        DIFFABLE_RECORD_TYPES.include?(record.type)
      end
    end

    def matches? record
      hash = existing
        .rdata[1..-2] # remove quotes
        .split(";")
        .reduce({}) do |hash, pair|
          type, short_names = pair.split(":")
          hash[type] = short_names.split(",")
          hash
        end
      shorthands = hash.fetch(record.type, [])
      shorthands.include?(generate_shorthand(record))
    end

    private

    def generate_rdata
      generate_manifest.map do |type, short_names|
        "#{type}:#{short_names.join(",")}"
      end.join(";").inspect
    end

    def generate_manifest
      records.select do |record|
        diffable?(record)
      end.reduce({}) do |hash, record|
        hash[record.type] ||= []
        hash[record.type] << generate_shorthand(record)
        hash[record.type].sort!
        hash
      end
    end

    def generate_shorthand record
      shorthand = record.short_name(zone.origin)
      if record.type == "MX"
        shorthand += " #{record.rdata[/^\d+/]}"
      end
      shorthand
    end
  end
end

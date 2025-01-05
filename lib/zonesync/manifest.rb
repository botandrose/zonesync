require "zonesync/record"
require "digest"

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
        name: "zonesync_manifest.#{zone.origin}",
        type: "TXT",
        ttl: zone.default_ttl || 3600,
        rdata: generate_rdata,
        comment: nil,
      )
    end

    def existing_checksum
      records.find(&:checksum?)
    end

    def generate_checksum
      input_string = diffable_records.map(&:to_s).join
      sha256 = Digest::SHA256.hexdigest(input_string)
      Record.new(
        name: "zonesync_checksum.#{zone.origin}",
        type: "TXT",
        ttl: zone.default_ttl || 3600,
        rdata: sha256.inspect,
        comment: nil,
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
      return false unless existing?
      hash = existing
        .rdata[1..-2] # remove quotes
        .split(";")
        .reduce({}) do |hash, pair|
          type, short_names = pair.split(":")
          hash[type] = short_names.split(",")
          hash
        end
      shorthands = hash.fetch(record.type, [])
      shorthands.include?(shorthand_for(record))
    end

    def shorthand_for record
      shorthand = record.short_name(zone.origin)
      if record.type == "MX"
        shorthand += " #{record.rdata[/^\d+/]}"
      end
      shorthand
    end

    private

    def generate_rdata
      generate_manifest.map do |type, short_names|
        "#{type}:#{short_names.join(",")}"
      end.join(";").inspect
    end

    def diffable_records
      records.select do |record|
        diffable?(record)
      end
    end

    def generate_manifest
      diffable_records.reduce({}) do |hash, record|
        hash[record.type] ||= []
        hash[record.type] << shorthand_for(record)
        hash[record.type].sort!
        hash
      end.sort_by(&:first)
    end
  end
end

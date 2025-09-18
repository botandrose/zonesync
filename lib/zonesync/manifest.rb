# typed: strict
require "sorbet-runtime"

require "zonesync/record"
require "zonesync/record_hash"
require "digest"

module Zonesync
  Manifest = Struct.new(:records, :zone) do
    extend T::Sig
    DIFFABLE_RECORD_TYPES =
      T.let(%w[A AAAA CNAME MX TXT SPF NAPTR PTR].sort, T::Array[String])

    sig { returns(T.nilable(Zonesync::Record)) }
    def existing
      records.find(&:manifest?)
    end

    sig { returns(T::Boolean) }
    def existing?
      !!existing
    end

    sig { returns(Zonesync::Record) }
    def generate
      generate_v2
    end

    sig { returns(T.nilable(Zonesync::Record)) }
    def existing_checksum
      records.find(&:checksum?)
    end

    sig { returns(Zonesync::Record) }
    def generate_checksum
      input_string = diffable_records.map(&:to_s).join
      sha256 = Digest::SHA256.hexdigest(input_string)
      Record.new(
        name: "zonesync_checksum.#{zone.origin}",
        type: "TXT",
        ttl: 3600,
        rdata: sha256.inspect,
        comment: nil,
      )
    end

    sig { returns(Zonesync::Record) }
    def generate_v2
      hashes = diffable_records.map { |record| RecordHash.generate(record) }
      Record.new(
        name: "zonesync_manifest.#{zone.origin}",
        type: "TXT",
        ttl: 3600,
        rdata: hashes.join(',').inspect,
        comment: nil,
      )
    end

    sig { params(record: Zonesync::Record).returns(T::Boolean) }
    def diffable? record
      if existing?
        matches?(record)
      else
        DIFFABLE_RECORD_TYPES.include?(record.type)
      end
    end

    sig { returns(T::Boolean) }
    def v1_format?
      return false unless existing?
      manifest_data = T.must(existing).rdata[1..-2]
      # V1 format uses "TYPE:" syntax, v2 uses comma-separated hashes
      manifest_data.include?(":") || manifest_data.include?(";")
    end

    sig { returns(T::Boolean) }
    def v2_format?
      return false unless existing?
      !v1_format?
    end

    sig { params(record: Zonesync::Record).returns(T::Boolean) }
    def matches? record
      return false unless existing?
      manifest_data = T.must(existing).rdata[1..-2] # remove quotes

      # Check if this is v2 format (comma-separated hashes) or v1 format (type:names)
      if manifest_data.include?(";")
        # V1 format: "A:@,mail;CNAME:www;MX:@ 10,@ 20"
        hash = manifest_data
          .split(";")
          .reduce({}) do |hash, pair|
            type, short_names = pair.split(":")
            hash[type] = short_names.split(",")
            hash
          end
        shorthands = hash.fetch(record.type, [])
        shorthands.include?(shorthand_for(record))
      else
        # V2 format: "1r81el0,60oib3,ky0g92,9pp0kg"
        expected_hashes = manifest_data.split(",")
        record_hash = RecordHash.generate(record)
        expected_hashes.include?(record_hash)
      end
    end

    sig { params(record: Zonesync::Record, with_type: T::Boolean).returns(String) }
    def shorthand_for record, with_type: false
      shorthand = record.short_name(zone.origin)
      shorthand = "#{record.type}:#{shorthand}" if with_type
      if record.type == "MX"
        shorthand += " #{record.rdata[/^\d+/]}"
      end
      shorthand
    end

    private

    sig { returns(String) }
    def generate_rdata
      generate_manifest.map do |type, short_names|
        "#{type}:#{short_names.join(",")}"
      end.join(";").inspect
    end

    sig { returns(T::Array[Zonesync::Record]) }
    def diffable_records
      records.select do |record|
        diffable?(record)
      end.sort
    end

    sig { returns(T::Hash[String, T::Array[String]]) }
    def generate_manifest
      hash = diffable_records.reduce({}) do |hash, record|
        hash[record.type] ||= []
        hash[record.type] << shorthand_for(record)
        hash[record.type].sort!
        hash
      end
      Hash[hash.sort_by(&:first)]
    end
  end
end

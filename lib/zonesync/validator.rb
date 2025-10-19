# typed: strict
require "sorbet-runtime"
require "zonesync/record_hash"

module Zonesync
  Validator = Struct.new(:operations, :destination, :source) do
    extend T::Sig

    sig { params(operations: T::Array[Operation], destination: Provider, source: T.nilable(Provider), force: T::Boolean).void }
    def self.call(operations, destination, source = nil, force: false)
      new(operations, destination, source).call(force: force)
    end

    sig { params(force: T::Boolean).void }
    def call(force: false)
      validation_error = ValidationError.new

      if !force && operations.any? && !manifest.existing?
        validation_error.add(MissingManifestError.new(manifest.generate))
      end

      if !force && manifest.v1_format? && manifest.existing_checksum && manifest.existing_checksum != manifest.generate_checksum
        validation_error.add(ChecksumMismatchError.new(manifest.existing_checksum, manifest.generate_checksum))
      end

      if !force && manifest.v2_format?
        integrity_error = validate_v2_manifest_integrity
        validation_error.add(integrity_error) if integrity_error
      end

      conflicts = operations.map do |method, args|
        method == :add ? validate_addition(args.first, force: force) : nil
      end.compact
      validation_error.add(ConflictError.new(conflicts)) if conflicts.any?

      if validation_error.errors.length == 1
        raise validation_error.errors.first
      elsif validation_error.errors.length > 1
        raise validation_error
      end

      nil
    end

    private

    sig { returns(Manifest) }
    def manifest
      destination.manifest
    end

    sig { returns(T.nilable(ChecksumMismatchError)) }
    def validate_v2_manifest_integrity
      manifest_data = T.must(manifest.existing).rdata[1..-2]
      expected_hashes = manifest_data.split(",")
      actual_records = Record.non_meta(destination.records)
      actual_hash_to_record = actual_records.map { |r| [RecordHash.generate(r), r] }.to_h

      missing_hash = expected_hashes.find { |hash| !actual_hash_to_record.key?(hash) }
      return nil unless missing_hash

      expected_record = find_expected_record(missing_hash)
      actual_record = find_modified_record(expected_record, actual_records)

      ChecksumMismatchError.new(
        expected_record: expected_record,
        actual_record: actual_record,
        missing_hash: missing_hash
      )
    end

    sig { params(missing_hash: String).returns(T.nilable(Record)) }
    def find_expected_record(missing_hash)
      return nil unless source

      source_records = Record.non_meta(source.records)
      source_records.find { |r| RecordHash.generate(r) == missing_hash }
    end

    sig { params(expected_record: T.nilable(Record), actual_records: T::Array[Record]).returns(T.nilable(Record)) }
    def find_modified_record(expected_record, actual_records)
      return nil unless expected_record

      # For CNAME and SOA, only one record per name is allowed, so check for modification
      # For other types (A, AAAA, TXT, MX), only check if there's exactly one record
      # with that name/type - if there are multiples, we can't determine which one it "became"
      if Record.single_record_per_name?(expected_record.type)
        actual_records.find do |r|
          r.name == expected_record.name && r.type == expected_record.type
        end
      else
        matching_records = actual_records.select do |r|
          r.name == expected_record.name && r.type == expected_record.type
        end
        matching_records.first if matching_records.count == 1
      end
    end

    sig { params(record: Record, force: T::Boolean).returns(T.nilable([T.nilable(Record), Record])) }
    def validate_addition record, force: false
      return nil if manifest.matches?(record)
      return nil if force

      conflicting_record = if manifest.v2_format?
        expected_hashes = manifest.existing.rdata[1..-2].split(",")
        find_v2_conflict(record, expected_hashes)
      elsif manifest.existing?
        find_v1_conflict(record)
      else
        find_unmanaged_conflict(record)
      end

      return nil if !conflicting_record
      return nil if conflicting_record == record
      [conflicting_record, record]
    end

    sig { params(record: Record, expected_hashes: T::Array[String]).returns(T.nilable(Record)) }
    def find_v2_conflict(record, expected_hashes)
      destination.records.find do |r|
        next if r.manifest? || r.checksum?
        next if expected_hashes.include?(RecordHash.generate(r))
        next if r.identical_to?(record)

        r.conflicts_with?(record)
      end
    end

    sig { params(record: Record).returns(T.nilable(Record)) }
    def find_v1_conflict(record)
      shorthand = manifest.shorthand_for(record, with_type: true)
      destination.records.find do |r|
        manifest.shorthand_for(r, with_type: true) == shorthand
      end
    end

    sig { params(record: Record).returns(T.nilable(Record)) }
    def find_unmanaged_conflict(record)
      destination.records.find do |r|
        r.identical_to?(record)
      end
    end
  end
end


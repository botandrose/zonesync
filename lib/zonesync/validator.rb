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
      if !force && operations.any? && !manifest.existing?
        raise MissingManifestError.new(manifest.generate)
      end
      # Only validate checksums for v1 manifests (v2 manifests provide integrity via hashes)
      if !force && manifest.v1_format? && manifest.existing_checksum && manifest.existing_checksum != manifest.generate_checksum
        raise ChecksumMismatchError.new(manifest.existing_checksum, manifest.generate_checksum)
      end
      # Validate v2 manifest integrity - check that all tracked records still exist with expected hashes
      if !force && manifest.v2_format?
        validate_v2_manifest_integrity
      end
      operations.each do |method, args|
        if method == :add
          validate_addition args.first, force: force
        end
      end
      nil
    end

    private

    sig { returns(Manifest) }
    def manifest
      destination.manifest
    end

    sig { void }
    def validate_v2_manifest_integrity
      # Extract expected hashes from the v2 manifest
      manifest_data = T.must(manifest.existing).rdata[1..-2] # remove quotes
      expected_hashes = manifest_data.split(",")

      # Get actual records in destination (excluding manifest/checksum records)
      actual_records = destination.records.reject { |r| r.manifest? || r.checksum? }

      # Build a map of hash to record for quick lookup
      actual_hash_to_record = actual_records.map { |r| [RecordHash.generate(r), r] }.to_h

      # Check if any expected hash is missing from actual hashes
      missing_hash = expected_hashes.find { |hash| !actual_hash_to_record.key?(hash) }

      if missing_hash
        # Find the expected record from source (if available)
        expected_record = nil
        if source
          source_records = source.records.reject { |r| r.manifest? || r.checksum? }
          expected_record = source_records.find { |r| RecordHash.generate(r) == missing_hash }
        end

        # Check if there's a modified version (same name/type but different content)
        # For CNAME and SOA, only one record per name is allowed, so check for modification
        # For other types (A, AAAA, TXT, MX), only check if there's exactly one record
        # with that name/type - if there are multiples, we can't determine which one it "became"
        actual_record = nil
        if expected_record
          if expected_record.type == "CNAME" || expected_record.type == "SOA"
            # These types only allow one record per name, so always check for modification
            actual_record = actual_records.find do |r|
              r.name == expected_record.name && r.type == expected_record.type
            end
          else
            # For types that allow multiples, only treat as modification if there's exactly one
            matching_records = actual_records.select do |r|
              r.name == expected_record.name && r.type == expected_record.type
            end
            actual_record = matching_records.first if matching_records.count == 1
          end
        end

        # Raise error with structured data
        raise ChecksumMismatchError.new(
          expected_record: expected_record,
          actual_record: actual_record,
          missing_hash: missing_hash
        )
      end
    end

    sig { params(record: Record, force: T::Boolean).void }
    def validate_addition record, force: false
      return if manifest.matches?(record)
      return if force

      # Use hash-based conflict detection when we have a v2 manifest
      if manifest.existing? && !manifest.existing.rdata[1..-2].include?(";")
        # V2 hash-based manifest: check for untracked records that conflict
        record_hash = RecordHash.generate(record)
        expected_hashes = manifest.existing.rdata[1..-2].split(",")

        # Find conflicting records that would be overwritten by this addition
        conflicting_record = destination.records.find do |r|
          next if r.manifest? || r.checksum?

          # Skip if this record is tracked in the manifest
          r_hash = RecordHash.generate(r)
          next if expected_hashes.include?(r_hash)

          # Skip if it's exactly the same record (we're just starting to track it)
          next if r.name == record.name && r.type == record.type && r.ttl == record.ttl && r.rdata == record.rdata

          # Check for conflicts based on record type
          case record.type
          when "CNAME", "SOA"
            # These types only allow one record per name
            r.name == record.name && r.type == record.type
          when "MX"
            # MX records conflict if same name and same priority (first part of rdata)
            if r.name == record.name && r.type == record.type
              existing_priority = r.rdata.split(' ').first
              new_priority = record.rdata.split(' ').first
              existing_priority == new_priority
            end
          else
            # For other types (A, AAAA, TXT, etc.), multiple records are allowed
            # Only conflict if trying to add identical record (but we already checked that above)
            false
          end
        end
      else
        # V1 name-based manifest or no manifest
        if manifest.existing?
          # V1 name-based manifest: use old shorthand logic
          shorthand = manifest.shorthand_for(record, with_type: true)
          conflicting_record = destination.records.find do |r|
            manifest.shorthand_for(r, with_type: true) == shorthand
          end
        else
          # No manifest: only conflict if exact same record exists
          conflicting_record = destination.records.find do |r|
            r.name == record.name &&
            r.type == record.type &&
            r.ttl == record.ttl &&
            r.rdata == record.rdata
          end
        end
      end

      return if !conflicting_record
      return if conflicting_record == record
      raise Zonesync::ConflictError.new(conflicting_record, record)
    end
  end
end


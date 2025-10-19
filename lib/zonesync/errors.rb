# typed: strict
require "sorbet-runtime"
require "zonesync/record_hash"

module Zonesync
  class ConflictError < StandardError
    extend T::Sig

    sig { params(existing: T.nilable(Record), new: Record).void }
    def initialize existing, new
      @existing = existing
      @new = new
    end

    sig { returns(String) }
    def message
      <<~MSG
        The following untracked DNS record already exists and would be overwritten.
          existing: #{@existing}
          new:      #{@new}
      MSG
    end
  end

  class MissingManifestError < StandardError
    extend T::Sig

    sig { params(manifest: Record).void }
    def initialize manifest
      @manifest = manifest
    end

    sig { returns(String) }
    def message
      <<~MSG
        The zonesync_manifest TXT record is missing. If this is the very first sync, make sure the Zonefile matches what's on the DNS server exactly. Otherwise, someone else may have removed it.
          manifest: #{@manifest}
      MSG
    end
  end

  class ChecksumMismatchError < StandardError
    extend T::Sig

    sig {
      params(
        existing: T.nilable(Record),
        new: T.nilable(Record),
        expected_record: T.nilable(Record),
        actual_record: T.nilable(Record),
        missing_hash: T.nilable(String)
      ).void
    }
    def initialize(existing = nil, new = nil, expected_record: nil, actual_record: nil, missing_hash: nil)
      @existing = existing
      @new = new
      @expected_record = expected_record
      @actual_record = actual_record
      @missing_hash = missing_hash
    end

    sig { returns(String) }
    def message
      # V2 manifest integrity violation
      if @missing_hash
        return generate_v2_message
      end

      # V1 checksum mismatch
      <<~MSG
        The zonesync_checksum TXT record does not match the current state of the DNS records. This probably means that someone else has changed them.
          existing: #{@existing}
          new:      #{@new}
      MSG
    end

    private

    sig { returns(String) }
    def generate_v2_message
      if @expected_record && @actual_record
        # Record was modified
        actual_hash = RecordHash.generate(@actual_record)
        <<~MSG.chomp
          The following tracked DNS record has been modified externally:
            Expected: #{@expected_record.name} #{@expected_record.ttl} #{@expected_record.type} #{@expected_record.rdata} (hash: #{@missing_hash})
            Actual:   #{@actual_record.name} #{@actual_record.ttl} #{@actual_record.type} #{@actual_record.rdata} (hash: #{actual_hash})

          This probably means someone else has changed it. Use --force to override.
        MSG
      elsif @expected_record
        # Record was deleted
        <<~MSG.chomp
          The following tracked DNS record has been deleted externally:
            Expected: #{@expected_record.name} #{@expected_record.ttl} #{@expected_record.type} #{@expected_record.rdata} (hash: #{@missing_hash})
            Not found in current remote records.

          This probably means someone else has deleted it. Use --force to override.
        MSG
      else
        # Fallback: we don't have source records to look up details
        <<~MSG.chomp
          The following tracked DNS record has been modified or deleted externally:
            Expected hash: #{@missing_hash} (not found in current records)

          This probably means someone else has changed it. Use --force to override.
        MSG
      end
    end
  end

  class DuplicateRecordError < StandardError
    extend T::Sig

    sig { params(record: Record, provider_message: T.nilable(String)).void }
    def initialize record, provider_message = nil
      @record = record
      @provider_message = provider_message
    end

    sig { returns(String) }
    def message
      msg = "Record already exists: #{@record.name} #{@record.type}"
      msg += " (#{@provider_message})" if @provider_message
      msg
    end

    sig { returns(Record) }
    attr_reader :record
  end
end


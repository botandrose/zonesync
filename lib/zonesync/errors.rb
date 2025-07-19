# typed: strict
require "sorbet-runtime"

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

    sig { params(existing: T.nilable(Record), new: Record).void }
    def initialize existing, new
      @existing = existing
      @new = new
    end

    sig { returns(String) }
    def message
      <<~MSG
        The zonesync_checksum TXT record does not match the current state of the DNS records. This probably means that someone else has changed them.
          existing: #{@existing}
          new:      #{@new}
      MSG
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


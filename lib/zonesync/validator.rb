module Zonesync
  class Validator < Struct.new(:operations, :destination)
    def self.call(...)
      new(...).call
    end

    def call
      if operations.any? && !manifest.existing?
        raise MissingManifestError.new(<<~MSG)
          The zonesync_manifest TXT record is missing. If this is the very first sync, make sure the Zonefile matches what's on the DNS server exactly. Otherwise, someone else may have removed it.
        MSG
      end
      if manifest.existing_checksum && manifest.existing_checksum != manifest.generate_checksum
        raise ChecksumMismatchError.new(<<~MSG)
          The zonesync_checksum TXT record does not match the current state of the DNS records. This probably means that someone else has changed them.
        MSG
      end
      operations.each do |method, args|
        send(method, *args)
      end
    end

    private

    def manifest
      destination.manifest
    end

    def add record
      return if manifest.matches?(record)
      conflicting_record = destination.records.find do |r|
        manifest.shorthand_for(r) == manifest.shorthand_for(record)
      end
      return if !conflicting_record
      return if conflicting_record == record
      raise Zonesync::ConflictError.new(<<~MSG)
        The following untracked DNS record already exists and would be overwritten.
          existing: #{conflicting_record}
          new:      #{record}
      MSG
    end

    def change *records
      # FIXME?
      # return unless manifest.existing?
      # return if records.map(&:to_h) == manifest.existing.to_h
      # manifest.change(*records)
    end

    def remove record
      # FIXME?
      # return unless manifest.existing?
      # return unless manifest.matches?(record)
      # manifest.remove(record)
    end
  end
end


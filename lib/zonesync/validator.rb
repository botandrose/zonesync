module Zonesync
  class Validator < Struct.new(:operations, :destination)
    def self.call(...)
      new(...).call
    end

    def call
      if operations.any? && !destination.manifest.existing?
        raise MissingManifestError.new(<<~MSG)
          The zonesync_manifest TXT record is missing. If this is the very first sync, make sure the Zonefile matches what's on the DNS server exactly. Otherwise, someone else may have removed it.
        MSG
      end
      operations.each do |method, args|
        send(method, *args)
      end
    end

    private

    def add record
      manifest = destination.manifest
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


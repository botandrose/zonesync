module Zonesync
  class Validator < Struct.new(:operations, :destination)
    def self.call(...)
      new(...).call
    end

    def call
      if operations.any? && !manifest.existing?
        raise MissingManifestError
      end
      if manifest.existing_checksum && manifest.existing_checksum != manifest.generate_checksum
        raise ChecksumMismatchError.new(manifest.existing_checksum, manifest.generate_checksum)
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
      raise Zonesync::ConflictError.new(conflicting_record, record)
    end

    def change *records
      # FIXME? is it possible to break something with a tracked changed record
    end

    def remove record
      # FIXME? is it possible to break something with a tracked removed record
    end
  end
end


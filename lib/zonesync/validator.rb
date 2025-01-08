# typed: strict
require "sorbet-runtime"

module Zonesync
  Validator = Struct.new(:operations, :destination) do
    extend T::Sig

    sig { params(operations: T::Array[Operation], destination: Provider).void }
    def self.call(operations, destination)
      new(operations, destination).call
    end

    sig { void }
    def call
      if operations.any? && !manifest.existing?
        raise MissingManifestError.new(manifest.generate)
      end
      if manifest.existing_checksum && manifest.existing_checksum != manifest.generate_checksum
        raise ChecksumMismatchError.new(manifest.existing_checksum, manifest.generate_checksum)
      end
      operations.each do |method, args|
        if method == :add
          validate_addition args.first
        end
      end
      nil
    end

    private

    sig { returns(Manifest) }
    def manifest
      destination.manifest
    end

    sig { params(record: Record).void }
    def validate_addition record
      return if manifest.matches?(record)
      shorthand = manifest.shorthand_for(record, with_type: true)
      conflicting_record = destination.records.find do |r|
        manifest.shorthand_for(r, with_type: true) == shorthand
      end
      return if !conflicting_record
      return if conflicting_record == record
      raise Zonesync::ConflictError.new(conflicting_record, record)
    end
  end
end


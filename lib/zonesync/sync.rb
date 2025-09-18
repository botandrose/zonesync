# typed: strict
require "sorbet-runtime"

require "zonesync/logger"

module Zonesync
  Sync = Struct.new(:source, :destination) do
    extend T::Sig

    sig { params(dry_run: T::Boolean, force: T::Boolean).void }
    def call dry_run: false, force: false
      operations = destination.diff!(source, force: force)

      smanifest = source.manifest.generate
      dmanifest = destination.manifest.existing
      if smanifest != dmanifest
        if dmanifest
          operations << [:change, [dmanifest, smanifest]]
        else
          operations << [:add, [smanifest]]
        end
      end

      # Only sync checksums for v1 manifests (v2 manifests provide integrity via hashes)
      source_will_generate_v2 = !source.manifest.existing? # No existing manifest = will generate v2
      dest_has_checksum = destination.manifest.existing_checksum
      dest_has_v1_manifest = destination.manifest.existing? && destination.manifest.v1_format?

      if source_will_generate_v2 && dest_has_checksum
        # Transitioning to v2: remove old checksum
        operations << [:remove, [dest_has_checksum]]
      elsif !source_will_generate_v2 && (source.manifest.v1_format? || dest_has_v1_manifest)
        # Both source and dest use v1 format: sync checksum
        schecksum = source.manifest.generate_checksum
        dchecksum = destination.manifest.existing_checksum
        if schecksum != dchecksum
          if dchecksum
            operations << [:change, [dchecksum, schecksum]]
          else
            operations << [:add, [schecksum]]
          end
        end
      end

      operations.each do |method, records|
        Logger.log(method, records, dry_run: dry_run)
        destination.send(method, *records) unless dry_run
      end
    end
  end
end

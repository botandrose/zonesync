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

      schecksum = source.manifest.generate_checksum
      dchecksum = destination.manifest.existing_checksum
      if schecksum != dchecksum
        if dchecksum
          operations << [:change, [dchecksum, schecksum]]
        else
          operations << [:add, [schecksum]]
        end
      end

      operations.each do |method, records|
        Logger.log(method, records, dry_run: dry_run)
        destination.send(method, *records) unless dry_run
      end
    end
  end
end

require "zonesync/provider"
require "zonesync/diff"
require "zonesync/validator"
require "zonesync/logger"
require "zonesync/cli"
require "zonesync/rake"
require "zonesync/errors"

module Zonesync
  def self.call source: "Zonefile", destination: "zonesync", dry_run: false
    Sync.new(
      { provider: "Filesystem", path: source },
      credentials[destination]
    ).call(dry_run: dry_run)
  end

  def self.generate source: "zonesync", destination: "Zonefile"
    Generate.new(
      credentials[source],
      { provider: "Filesystem", path: destination }
    ).call
  end

  def self.credentials
    require "active_support"
    require "active_support/encrypted_configuration"
    require "active_support/core_ext/hash/keys"
    ActiveSupport::EncryptedConfiguration.new(
      config_path: "config/credentials.yml.enc",
      key_path: "config/master.key",
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true,
    )
  end

  class Sync < Struct.new(:source, :destination)
    def call dry_run: false
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      operations = Diff.call(
        from: destination.diffable_records,
        to: source.diffable_records,
      )

      Validator.call(operations, destination)

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

      operations.each do |method, args|
        Logger.log(method, args, dry_run: dry_run)
        destination.send(method, *args) unless dry_run
      end
    end
  end

  class Generate < Struct.new(:source, :destination)
    def call
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      destination.write(source.read)
    end
  end
end


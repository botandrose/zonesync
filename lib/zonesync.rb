# typed: strict
require "sorbet-runtime"

require "zonesync/provider"
require "zonesync/diff"
require "zonesync/validator"
require "zonesync/logger"
require "zonesync/cli"
require "zonesync/rake"
require "zonesync/errors"

begin # optional active_support dependency
  require "active_support"
  require "active_support/encrypted_configuration"
  require "active_support/core_ext/hash/keys"
rescue LoadError; end

module Zonesync
  extend T::Sig

  sig { params(source: T.nilable(String), destination: T.nilable(String), dry_run: T::Boolean).void }
  def self.call source: "Zonefile", destination: "zonesync", dry_run: false
    source = T.must(source)
    destination = T.must(destination).to_sym
    Sync.new(
      Provider.from({ provider: "Filesystem", path: source }),
      Provider.from(credentials(destination)),
    ).call(dry_run: dry_run)
  end

  sig { params(source: T.nilable(String), destination: T.nilable(String)).void }
  def self.generate source: "zonesync", destination: "Zonefile"
    source = T.must(source).to_sym
    Generate.new(
      Provider.from(credentials(source)),
      Provider.from({ provider: "Filesystem", path: T.must(destination) }),
    ).call
  end

  sig { params(key: Symbol).returns(T::Hash[Symbol, String]) }
  def self.credentials key
    ActiveSupport::EncryptedConfiguration.new(
      config_path: "config/credentials.yml.enc",
      key_path: "config/master.key",
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true,
    ).config[key]
  end

  Sync = Struct.new(:source, :destination) do
    extend T::Sig

    sig { params(dry_run: T::Boolean).void }
    def call dry_run: false
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

      operations.each do |method, records|
        Logger.log(method, records, dry_run: dry_run)
        destination.send(method, *records) unless dry_run
      end
    end
  end

  Generate = Struct.new(:source, :destination) do
    extend T::Sig

    sig { void }
    def call
      destination.write(source.read)
      nil
    end
  end
end


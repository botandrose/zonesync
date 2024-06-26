require "zonesync/provider"
require "zonesync/diff"
require "zonesync/logger"
require "zonesync/cli"
require "zonesync/rake"

module Zonesync
  def self.call zonefile: "Zonefile", credentials: default_credentials, dry_run: false
    Sync.new({ provider: "Filesystem", path: zonefile }, credentials).call(dry_run: dry_run)
  end

  def self.generate zonefile: "Zonefile", credentials: default_credentials
    Generate.new({ provider: "Filesystem", path: zonefile }, credentials).call
  end

  def self.default_credentials
    require "active_support"
    require "active_support/encrypted_configuration"
    require "active_support/core_ext/hash/keys"
    ActiveSupport::EncryptedConfiguration.new(
      config_path: "config/credentials.yml.enc",
      key_path: "config/master.key",
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true,
    ).zonesync
  end

  def self.default_provider
    Provider.from(default_credentials)
  end

  class Sync < Struct.new(:source, :destination)
    def call dry_run: false
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      operations = Diff.call(from: destination, to: source)
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
      source.write(destination.read)
    end
  end
end


# frozen_string_literal: true

require "zonesync/sync"
require "zonesync/generate"
require "zonesync/provider"
require "zonesync/cli"
require "zonesync/rake"
require "zonesync/errors"
require "zonesync/record_hash"

begin # optional active_support dependency
  require "active_support"
  require "active_support/encrypted_configuration"
  require "active_support/core_ext/hash/keys"
rescue LoadError; end

module Zonesync
  def self.call(source: "Zonefile", destination: "zonesync", dry_run: false, force: false)
    Sync.new(
      Provider.from({ provider: "Filesystem", path: source }),
      Provider.from(credentials(destination.to_sym)),
    ).call(dry_run: dry_run, force: force)
  end

  def self.generate(source: "zonesync", destination: "Zonefile")
    Generate.new(
      Provider.from(credentials(source.to_sym)),
      Provider.from({ provider: "Filesystem", path: destination }),
    ).call
  end

  def self.credentials(key)
    ActiveSupport::EncryptedConfiguration.new(
      config_path: "config/credentials.yml.enc",
      key_path: "config/master.key",
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true,
    ).config[key]
  end
end

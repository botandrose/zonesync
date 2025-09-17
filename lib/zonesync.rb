# typed: strict
require "sorbet-runtime"

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
  extend T::Sig

  sig { params(source: T.nilable(String), destination: T.nilable(String), dry_run: T::Boolean, force: T::Boolean).void }
  def self.call source: "Zonefile", destination: "zonesync", dry_run: false, force: false
    source = T.must(source)
    destination = T.must(destination).to_sym
    Sync.new(
      Provider.from({ provider: "Filesystem", path: source }),
      Provider.from(credentials(destination)),
    ).call(dry_run: dry_run, force: force)
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
end


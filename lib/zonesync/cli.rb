require "thor"

module Zonesync
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    default_command :sync
    desc "sync", "syncs the contents of Zonefile to the DNS server configured in Rails.application.credentials.zonesync"
    method_option :dry_run, type: :boolean, default: false, aliases: :n, desc: "log operations to STDOUT but don't perform the sync"
    def sync
      Zonesync.call credentials: default_credentials, dry_run: options[:dry_run]
    end

    private

    def default_credentials
      if defined?(Rails.application.credentials)
        Rails.application.credentials.zonesync
      else
        require "active_support/encrypted_configuration"
        require "active_support/core_ext/hash/keys"
        credentials = ActiveSupport::EncryptedConfiguration.new(config_path: "config/credentials.yml.enc", key_path: "config/master.key", raise_if_missing_key: true, env_key: "RAILS_MASTER_KEY")
        credentials.zonesync
      end
    end
  end
end

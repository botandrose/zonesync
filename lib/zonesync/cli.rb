require "thor"

module Zonesync
  class CLI < Thor
    default_command :sync
    desc "sync", "syncs the contents of Zonefile to the DNS server configured in Rails.application.credentials.zonesync"
    method_option :dry_run, type: :boolean, default: false, aliases: :n, desc: "log operations to STDOUT but don't perform the sync"
    def sync
      Zonesync.call dry_run: options[:dry_run]
    rescue ConflictError, MissingManifestError, ChecksumMismatchError => e
      puts e.message
      exit 1
    end

    desc "generate", "generates a Zonefile from the DNS server configured in Rails.application.credentials.zonesync"
    def generate
      Zonesync.generate
    end

    def self.exit_on_failure? = true
  end
end

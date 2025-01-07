# typed: strict
require "sorbet-runtime"

require "thor"

module Zonesync
  class CLI < Thor
    extend T::Sig

    default_command :sync
    desc "sync --source=Zonefile --destination=zonesync", "syncs the contents of the Zonefile to the DNS server configured in Rails.application.credentials.zonesync"
    option :source, default: "Zonefile", desc: "path to the zonefile"
    option :destination, default: "zonesync", desc: "key to the DNS server configuration in Rails.application.credentials"
    method_option :dry_run, type: :boolean, default: false, aliases: :n, desc: "log operations to STDOUT but don't perform the sync"
    sig { void }
    def sync
      kwargs = options.to_hash.transform_keys(&:to_sym)
      Zonesync.call(**kwargs)
    rescue ConflictError, MissingManifestError, ChecksumMismatchError => e
      puts e.message
      exit 1
    end

    desc "generate --source=zonesync --destination=Zonefile", "generates a Zonefile from the DNS server configured in Rails.application.credentials.zonesync"
    option :source, default: "zonesync", desc: "key to the DNS server configuration in Rails.application.credentials"
    option :destination, default: "Zonefile", desc: "path to the zonefile"
    sig { void }
    def generate
      kwargs = options.to_hash.transform_keys(&:to_sym)
      Zonesync.generate(**kwargs)
    end

    sig { returns(TrueClass) }
    def self.exit_on_failure? = true
  end
end

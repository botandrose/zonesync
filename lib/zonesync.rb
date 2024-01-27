require "dns/zonefile"
require "net/http"

module Zonesync
  def self.call zonefile:, credentials:
    Sync.new(zonefile, credentials).call
  end

  class Sync < Struct.new(:zonefile, :credentials)
    def call
      local = Provider.new({ provider: "Filesystem", path: zonefile })
      remote = Provider.new(credentials)
      operations = Diff.call(from: remote, to: local)
      operations.each { |operation| remote.apply(operation) }
    end
  end

  class Diff < Struct.new(:from, :to)
    def self.call(from:, to:)
      new(from, to).call
    end

    def call
      []
    end
  end

  class Provider < Struct.new(:credentials)
    def zonefile
      contents = send(credentials[:provider])
      DNS::Zonefile.load(contents)
    end

    def Filesystem
      File.read(credentials[:path])
    end

    def Cloudflare
      `curl --request GET \\
        --url "https://api.cloudflare.com/client/v4/zones/#{credentials.zone_id}/dns_records/export" \\
        --header "Content-Type: application/json" \\
        --header "X-Auth-Email: #{credentials.email}" \\
        --header "X-Auth-Key: #{credentials.key}"`
    end

    def apply op
    end

    def diffable_records
      zonefile.records.select { |record| record_types.include? record.class }
    end

    private

    def record_types
      [DNS::Zonefile::A, DNS::Zonefile::AAAA, DNS::Zonefile::CNAME, DNS::Zonefile::MX]
    end
  end
end

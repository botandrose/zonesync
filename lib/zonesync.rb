require "dns/zonefile"
require "net/http"
require "diff/lcs"

module DNS
  module Zonefile
    class Record
      def == other
        to_h == other.to_h
      end

      def to_h
        (instance_variables - [:@vars]).reduce({ class: self.class }) do |hash, key|
          new_key = key.to_s.sub("@","").to_sym
          hash.merge new_key => instance_variable_get(key)
        end
      end
    end
  end
end

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
      changes = ::Diff::LCS.sdiff(from.diffable_records, to.diffable_records)
      changes.map do |change|
        case change.action
        when "-"
          [:remove, change.old_element.to_h]
        when "!"
          [:change, [change.old_element.to_h, change.new_element.to_h]]
        when "+"
          [:add, change.new_element.to_h]
        end
      end.compact
    end
  end

  class Provider < Struct.new(:credentials)
    def zonefile
      contents = send(credentials[:provider])
      DNS::Zonefile.load(contents)
    end

    def String
      credentials[:string]
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

    def apply ops
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

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
        (instance_variables - [:@vars, :@klass]).reduce({ type: self.class.to_s.split("::").last }) do |hash, key|
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
      operations.each { |method, args| puts [method, *args].inspect }
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
      @adapter = Zonesync.const_get(credentials[:provider]).new(credentials)
      DNS::Zonefile.load(@adapter.read)
    end

    %i[read remove change add].each do |method|
      define_method method do |*args|
        @adapter.send(method, *args)
      end
    end

    def diffable_records
      diffable_record_types = [
        DNS::Zonefile::A,
        DNS::Zonefile::AAAA,
        DNS::Zonefile::CNAME,
        DNS::Zonefile::MX,
        DNS::Zonefile::TXT,
      ]
      zonefile.records.select do |record|
        diffable_record_types.include?(record.class)
      end
    end
  end

  require "zonesync/cloudflare"

  class Memory < Provider
    def read
      credentials[:string]
    end

    def remove record
      raise NotImplementedError
    end

    def change old_record, new_record
      raise NotImplementedError
    end

    def add record
      raise NotImplementedError
    end
  end

  class Filesystem < Provider
    def read
      File.read(credentials[:path])
    end

    def remove record
      raise NotImplementedError
    end

    def change old_record, new_record
      raise NotImplementedError
    end

    def add record
      raise NotImplementedError
    end
  end
end

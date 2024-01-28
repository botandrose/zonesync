require "dns/zonefile"
require "zonesync/provider"
require "zonesync/diff"

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
end


require "zonesync/provider"
require "zonesync/diff"

module Zonesync
  def self.call zonefile:, credentials:
    Sync.new(zonefile, credentials).call
  end

  class Sync < Struct.new(:zonefile, :credentials)
    def call
      local = Provider.from({ provider: "Filesystem", path: zonefile })
      remote = Provider.from(credentials)
      operations = Diff.call(from: remote, to: local)
      operations.each do |method, args|
        puts [method, args].inspect
        remote.send(method, args)
      end
    end
  end
end


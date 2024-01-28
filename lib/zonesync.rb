require "zonesync/provider"
require "zonesync/diff"

module Zonesync
  def self.call zonefile:, credentials:
    Sync.new({ provider: "Filesystem", path: zonefile }, credentials).call
  end

  class Sync < Struct.new(:source, :destination)
    def call
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      operations = Diff.call(from: destination, to: source)
      operations.each do |method, args|
        puts [method, args].inspect
        destination.send(method, args)
      end
    end
  end
end


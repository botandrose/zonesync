require "zonesync/provider"
require "zonesync/diff"
require "zonesync/logger"
require "zonesync/cli"

module Zonesync
  def self.call zonefile: "Zonefile", credentials:
    Sync.new({ provider: "Filesystem", path: zonefile }, credentials).call
  end

  class Sync < Struct.new(:source, :destination)
    def call
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      operations = Diff.call(from: destination, to: source)
      operations.each do |method, args|
        Logger.log(method, args)
        destination.send(method, args)
      end
    end
  end
end


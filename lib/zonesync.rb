require "zonesync/provider"
require "zonesync/diff"
require "zonesync/logger"
require "zonesync/cli"

module Zonesync
  def self.call zonefile: "Zonefile", credentials:, dry_run: false
    Sync.new({ provider: "Filesystem", path: zonefile }, credentials).call(dry_run: dry_run)
  end

  class Sync < Struct.new(:source, :destination)
    def call dry_run: false
      source = Provider.from(self.source)
      destination = Provider.from(self.destination)
      operations = Diff.call(from: destination, to: source)
      operations.each do |method, args|
        Logger.log(method, args, dry_run: dry_run)
        destination.send(method, args) unless dry_run
      end
    end
  end
end


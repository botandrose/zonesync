# typed: strict
require "sorbet-runtime"
require "zlib"

module Zonesync
  module RecordHash
    extend T::Sig

    sig { params(record: Record).returns(String) }
    def self.generate(record)
      identity = "#{record.name}:#{record.type}:#{record.ttl}:#{record.rdata}"
      Zlib.crc32(identity).to_s(36)
    end
  end
end
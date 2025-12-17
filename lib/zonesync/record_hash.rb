# frozen_string_literal: true

require "zlib"

module Zonesync
  module RecordHash
    def self.generate(record)
      identity = "#{record.name}:#{record.type}:#{record.ttl}:#{record.rdata}"
      Zlib.crc32(identity).to_s(36)
    end
  end
end

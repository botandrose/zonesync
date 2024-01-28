module Zonesync
  class Record < Struct.new(:name, :type, :ttl, :rdata)
  end
end


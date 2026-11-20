# frozen_string_literal: true

module Zonesync
  class Route53 < Provider
    class Source < Provider
      def initialize(source)
        super(source.config)
        @source = source
      end

      def read
        @source.read
      end

      def write(string)
        @source.write(string)
      end

      def records
        AliasRecord.adopt(super)
      end
    end
  end
end

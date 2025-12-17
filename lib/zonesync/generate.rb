# frozen_string_literal: true

module Zonesync
  Generate = Struct.new(:source, :destination) do
    def call
      destination.write(source.read)
      nil
    end
  end
end

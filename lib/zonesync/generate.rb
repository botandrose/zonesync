# typed: strict
require "sorbet-runtime"

module Zonesync
  Generate = Struct.new(:source, :destination) do
    extend T::Sig

    sig { void }
    def call
      destination.write(source.read)
      nil
    end
  end
end

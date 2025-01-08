# typed: strict
require "sorbet-runtime"

require "diff/lcs"

module Zonesync
  Operation = T.type_alias { [Symbol, T::Array[Record]] }

  Diff = Struct.new(:from, :to) do
    extend T::Sig

    sig { params(from: T::Array[Record], to: T::Array[Record]).returns(T.untyped) }
    def self.call(from:, to:)
      new(from, to).call
    end

    sig { returns(T::Array[[Symbol, T::Array[Record]]]) }
    def call
      changes = ::Diff::LCS.sdiff(from, to)
      changes.map do |change|
        case change.action
        when "-"
          [:remove, [change.old_element]]
        when "!"
          [:change, [change.old_element, change.new_element]]
        when "+"
          [:add, [change.new_element]]
        end
      end.compact.sort_by do |operation|
        operation.first
      end.reverse # perform remove operations first
    end
  end
end


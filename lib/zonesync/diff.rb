require "diff/lcs"

module Zonesync
  class Diff < Struct.new(:from, :to)
    def self.call(from:, to:)
      new(from, to).call
    end

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


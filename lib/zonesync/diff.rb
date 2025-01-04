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
          [:remove, [change.old_element.to_h]]
        when "!"
          [:change, [change.old_element.to_h, change.new_element.to_h]]
        when "+"
          [:add, [change.new_element.to_h]]
        end
      end.compact
    end
  end
end


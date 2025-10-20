# typed: strict
require "sorbet-runtime"

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
      # Group records by their primary key (name + type)
      from_by_key = from.group_by { |r| [r.name, r.type] }
      to_by_key = to.group_by { |r| [r.name, r.type] }

      operations = []

      # Process all keys that exist in from
      from_by_key.each do |key, from_records|
        to_records = to_by_key[key] || []

        if to_records.empty?
          # All records with this key were removed
          from_records.each { |r| operations << [:remove, [r]] }
        elsif from_records.length == 1 && to_records.length == 1
          # Single record with this key - check if it changed
          from_record = from_records.first
          to_record = to_records.first

          unless from_record == to_record
            operations << [:change, [from_record, to_record]]
          end
        else
          # Multiple records with same name+type, or count mismatch
          # Use set difference to find what was added/removed
          removed = from_records - to_records
          added = to_records - from_records

          removed.each { |r| operations << [:remove, [r]] }
          added.each { |r| operations << [:add, [r]] }
        end
      end

      # Process keys that only exist in to (new records)
      to_by_key.each do |key, to_records|
        unless from_by_key.key?(key)
          to_records.each { |r| operations << [:add, [r]] }
        end
      end

      # Sort operations (remove first)
      operations.sort_by { |op| op.first }.reverse
    end
  end
end


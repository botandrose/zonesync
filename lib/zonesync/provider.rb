# frozen_string_literal: true

require "zonesync/record"
require "zonesync/zonefile"
require "zonesync/manifest"
require "zonesync/diff"
require "zonesync/validator"

module Zonesync
  class Provider
    def initialize(config)
      @config = config
    end
    attr_reader :config

    def self.from(config)
      Zonesync.const_get(config.fetch(:provider)).new(config)
    end

    def diff!(other, force: false)
      operations = diff(other).call
      Validator.call(operations, self, other, force: force)
      operations
    end

    def diff(other)
      Diff.new(
        from: diffable_records,
        to: other.diffable_records,
      )
    end

    def records
      zonefile.records
    end

    def diffable_records
      records.select do |record|
        manifest.diffable?(record)
      end.sort
    end

    def manifest
      Manifest.new(records, zonefile)
    end

    private def zonefile
      @zonefile ||= Zonefile.load(read)
    end

    def read
      raise NotImplementedError
    end

    def write(string)
      raise NotImplementedError
    end

    def remove(record)
      raise NotImplementedError
    end

    def change(old_record, new_record)
      raise NotImplementedError
    end

    def add(record)
      raise NotImplementedError
    end

    def add_with_duplicate_handling(record, &block)
      begin
        block.call
      rescue DuplicateRecordError => e
        puts "Record already exists in #{self.class.name}: #{e.record.name} #{e.record.type} - will start tracking it"
        return
      end
    end

    private

    def hash_based_diffable_records(remote_records, expected_hashes)
      require 'set'
      expected_set = Set.new(expected_hashes)
      found_set = Set.new
      diffable = []

      remote_records.each do |record|
        hash = RecordHash.generate(record)
        if expected_set.include?(hash)
          found_set.add(hash)
          diffable << record
        end
      end

      missing = expected_set - found_set
      if missing.any?
        raise ConflictError.new([[nil, diffable.first || remote_records.first]])
      end

      diffable.sort
    end
  end

  require "zonesync/cloudflare"
  require "zonesync/route53"

  class Memory < Provider
    def read
      config.fetch(:string)
    end

    def write(string)
      config[:string] = string
      nil
    end
  end

  class Filesystem < Provider
    def read
      File.read(config.fetch(:path))
    end

    def write(string)
      File.write(config.fetch(:path), string)
      nil
    end
  end
end

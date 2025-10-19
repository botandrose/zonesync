# typed: strict
require "sorbet-runtime"

require "zonesync/record"
require "zonesync/zonefile"
require "zonesync/manifest"
require "zonesync/diff"
require "zonesync/validator"

module Zonesync
  class Provider
    extend T::Sig

    sig { params(config: T::Hash[Symbol, String]).void }
    def initialize config
      @config = T.let(config, T::Hash[Symbol, String])
    end
    sig { returns(T::Hash[Symbol, String]) }
    attr_reader :config

    sig { params(config: T::Hash[Symbol, String]).returns(Provider) }
    def self.from config
      Zonesync.const_get(config.fetch(:provider)).new(config)
    end

    sig { params(other: Provider, force: T::Boolean).returns(T::Array[Operation]) }
    def diff! other, force: false
      operations = diff(other).call
      Validator.call(operations, self, other, force: force)
      operations
    end

    sig { params(other: Provider).returns(Diff) }
    def diff other
      Diff.new(
        from: diffable_records,
        to: other.diffable_records,
      )
    end

    sig { returns(T::Array[Record]) }
    def records
      zonefile.records
    end

    sig { returns(T::Array[Record]) }
    def diffable_records
      records.select do |record|
        manifest.diffable?(record)
      end.sort
    end

    sig { returns(Manifest) }
    def manifest
      Manifest.new(records, zonefile)
    end

    sig { returns(Zonefile) }
    private def zonefile
      @zonefile ||= T.let(Zonefile.load(read), T.nilable(Zonefile))
    end

    sig { returns(String) }
    def read
      Kernel.raise NotImplementedError
    end

    sig { params(string: String).void }
    def write string
      Kernel.raise NotImplementedError
    end

    sig { params(record: Record).void }
    def remove record
      Kernel.raise NotImplementedError
    end

    sig { params(old_record: Record, new_record: Record).void }
    def change old_record, new_record
      Kernel.raise NotImplementedError
    end

    sig { params(record: Record).void }
    def add record
      Kernel.raise NotImplementedError
    end

    # Helper method for graceful duplicate record handling
    # Child classes can use this in their add method implementations
    sig { params(record: Record, block: T.proc.void).void }
    def add_with_duplicate_handling record, &block
      begin
        block.call
      rescue DuplicateRecordError => e
        # Gracefully handle duplicate records - this means the record
        # already exists and we just want to start tracking it
        puts "Record already exists in #{self.class.name}: #{e.record.name} #{e.record.type} - will start tracking it"
        return
      end
    end

    private

    sig { params(remote_records: T::Array[Record], expected_hashes: T::Array[String]).returns(T::Array[Record]) }
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
    extend T::Sig

    sig { returns(String) }
    def read
      config.fetch(:string)
    end

    sig { params(string: String).void }
    def write string
      config[:string] = string
      nil
    end
  end

  class Filesystem < Provider
    extend T::Sig

    sig { returns(String) }
    def read
      File.read(config.fetch(:path))
    end

    sig { params(string: String).void }
    def write string
      File.write(config.fetch(:path), string)
      nil
    end
  end
end


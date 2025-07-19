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

    sig { params(other: Provider).returns(T::Array[Operation]) }
    def diff! other
      operations = diff(other).call
      Validator.call(operations, self)
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


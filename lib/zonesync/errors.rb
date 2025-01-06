module Zonesync
  class ConflictError < StandardError
    def initialize existing, new
      @existing = existing
      @new = new
    end

    def message
      <<~MSG
        The following untracked DNS record already exists and would be overwritten.
          existing: #{@existing}
          new:      #{@new}
      MSG
    end
  end

  class MissingManifestError < StandardError
    def initialize manifest
      @manifest = manifest
    end

    def message
      <<~MSG
        The zonesync_manifest TXT record is missing. If this is the very first sync, make sure the Zonefile matches what's on the DNS server exactly. Otherwise, someone else may have removed it.
          manifest: #{@manifest}
      MSG
    end
  end

  class ChecksumMismatchError < StandardError
    def initialize existing, new
      @existing = existing
      @new = new
    end

    def message
      <<~MSG
        The zonesync_checksum TXT record does not match the current state of the DNS records. This probably means that someone else has changed them.
          existing: #{@existing}
          new:      #{@new}
      MSG
    end
  end
end


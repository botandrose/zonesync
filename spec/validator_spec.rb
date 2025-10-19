require "zonesync"

describe Zonesync::Validator do
  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

  context "with checksum mismatch" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "A:@"
      zonesync_checksum TXT   "BADCHECKSUM"
    RECORDS

    it "raises ChecksumMismatchError by default" do
      operations = []
      expect {
        described_class.call(operations, destination)
      }.to raise_error(Zonesync::ChecksumMismatchError)
    end

    it "does not raise error when force is true" do
      operations = []
      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end

    it "raises ChecksumMismatchError when force is explicitly false" do
      operations = []
      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::ChecksumMismatchError)
    end
  end

  context "without existing checksum" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "A:@"
    RECORDS

    it "does not raise error regardless of force flag" do
      operations = []
      expect {
        described_class.call(operations, destination, force: false)
      }.not_to raise_error

      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end
  end

  context "with missing manifest" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
    RECORDS

    it "raises MissingManifestError by default but not with force flag" do
      operations = [[:add, [Zonesync::Record.new(name: "test.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil)]]]

      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::MissingManifestError)

      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end
  end

  context "with hash-based manifest and untracked conflicting records" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      @                 MX    10 mail.example.com.
      @                 MX    20 mail2.example.com.
      zonesync_manifest TXT   "1r81el0,9pp0kg"
      zonesync_checksum TXT   "131e8dbd474ffba7c520c1a40830b1800e89a67c6c5c96e570016f5fc23e6074"
    RECORDS

    it "raises ConflictError when adding record that conflicts with untracked record" do
      # This record conflicts with the existing untracked MX 20 mail2.example.com.
      new_record = Zonesync::Record.new(
        name: "example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "20 mail.example.com.",
        comment: nil
      )
      operations = [[:add, [new_record]]]

      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::ConflictError, /The following untracked DNS record already exists and would be overwritten/)
    end

    it "does not raise ConflictError when adding non-conflicting record" do
      # This record does not conflict
      new_record = Zonesync::Record.new(
        name: "example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "30 mail3.example.com.",
        comment: nil
      )
      operations = [[:add, [new_record]]]

      expect {
        described_class.call(operations, destination, force: false)
      }.not_to raise_error
    end

    it "does not raise ConflictError when force is true" do
      # Even conflicting records should be allowed with force
      new_record = Zonesync::Record.new(
        name: "example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "20 mail.example.com.",
        comment: nil
      )
      operations = [[:add, [new_record]]]

      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end
  end

  context "with v2 hash-based manifest (checksum-free)" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "1r81el0"
    RECORDS

    it "does not validate checksums for v2 manifests" do
      operations = []
      # Should not raise ChecksumMismatchError even though no checksum exists
      expect {
        described_class.call(operations, destination, force: false)
      }.not_to raise_error
    end

    it "does not validate checksums even when checksum record exists" do
      destination_with_checksum = Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS })
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 A     192.0.2.1
        zonesync_manifest TXT   "1r81el0"
        zonesync_checksum TXT   "BADCHECKSUM"
      RECORDS

      operations = []
      # Should not raise ChecksumMismatchError for v2 manifests even with bad checksum
      expect {
        described_class.call(operations, destination_with_checksum, force: false)
      }.not_to raise_error
    end
  end

  context "with v1 name-based manifest (checksum required)" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "A:@"
      zonesync_checksum TXT   "BADCHECKSUM"
    RECORDS

    it "still validates checksums for v1 manifests" do
      operations = []
      # Should still raise ChecksumMismatchError for v1 manifests
      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::ChecksumMismatchError)
    end
  end

  context "with v2 manifest integrity validation" do
    # Hash for @ A 3600 192.0.2.1 is 1r81el0
    # Hash for ssh A 3600 192.0.2.2 is 10v6j8z
    # Hash for ssh A 3600 192.0.2.99 is kqsxr1 (modified version)

    context "when tracked record has been modified externally" do
      let(:destination_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 A     192.0.2.1
        ssh               A     192.0.2.99
        zonesync_manifest TXT   "1r81el0,10v6j8z"
      RECORDS

      let(:source_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
        ssh  A     192.0.2.2
      RECORDS

      let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

      it "raises ChecksumMismatchError when manifest hash doesn't match actual record" do
        operations = []
        # Manifest says ssh should have hash 10v6j8z (ssh.example.com. 3600 A 192.0.2.2)
        # But destination has hash kqsxr1 (ssh.example.com. 3600 A 192.0.2.99)
        expect {
          described_class.call(operations, destination, source, force: false)
        }.to raise_error(Zonesync::ChecksumMismatchError) do |error|
          # Error should show which record was modified and what changed
          expect(error.message).to eq(<<~MSG.chomp)
            The following tracked DNS record has been modified externally:
              Expected: ssh.example.com. 3600 A 192.0.2.2 (hash: 10v6j8z)
              Actual:   ssh.example.com. 3600 A 192.0.2.99 (hash: kqsxr1)

            This probably means someone else has changed it. Use --force to override.
          MSG
        end
      end

      it "does not raise error when force is true" do
        operations = []
        expect {
          described_class.call(operations, destination, source, force: true)
        }.not_to raise_error
      end
    end

    context "when tracked record has been deleted externally" do
      let(:destination_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 A     192.0.2.1
        zonesync_manifest TXT   "1r81el0,10v6j8z"
      RECORDS

      let(:source_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
        ssh  A     192.0.2.2
      RECORDS

      let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

      it "raises ChecksumMismatchError when tracked record is missing" do
        operations = []
        # Manifest says ssh should exist with hash 10v6j8z (ssh.example.com. 3600 A 192.0.2.2)
        # Source has ssh, but it's been deleted from destination
        expect {
          described_class.call(operations, destination, source, force: false)
        }.to raise_error(Zonesync::ChecksumMismatchError) do |error|
          # Error should show the expected record that's missing
          expect(error.message).to eq(<<~MSG.chomp)
            The following tracked DNS record has been deleted externally:
              Expected: ssh.example.com. 3600 A 192.0.2.2 (hash: 10v6j8z)
              Not found in current remote records.

            This probably means someone else has deleted it. Use --force to override.
          MSG
        end
      end
    end

    context "when all tracked records match" do
      let(:destination_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 A     192.0.2.1
        ssh               A     192.0.2.2
        zonesync_manifest TXT   "1r81el0,10v6j8z"
      RECORDS

      let(:source_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
        ssh  A     192.0.2.2
      RECORDS

      let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

      it "does not raise error when all hashes match" do
        operations = []
        expect {
          described_class.call(operations, destination, source, force: false)
        }.not_to raise_error
      end
    end

    context "when untracked records exist (added externally)" do
      # Hash for @ A 3600 192.0.2.1 is 1r81el0
      # Hash for www A 3600 192.0.2.10 is 1vxweh9 (untracked - added externally)
      let(:destination_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 A     192.0.2.1
        www               A     192.0.2.10
        zonesync_manifest TXT   "1r81el0"
      RECORDS

      let(:source_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
      RECORDS

      let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

      it "ignores untracked records and does not raise error" do
        operations = []
        # Manifest only tracks @ record (1r81el0)
        # www record (1vxweh9) was added externally and is NOT in manifest
        # The integrity check should only validate that @ still exists and hasn't changed
        # It should completely ignore the untracked www record
        expect {
          described_class.call(operations, destination, source, force: false)
        }.not_to raise_error
      end

      it "still detects if a tracked record is modified even with untracked records present" do
        destination_with_modified_tracked = Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS })
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.99
          www               A     192.0.2.10
          zonesync_manifest TXT   "1r81el0"
        RECORDS

        operations = []
        # Manifest tracks @ with hash 1r81el0 (192.0.2.1)
        # But @ was changed to 192.0.2.99 (different hash)
        # Even though www is untracked, the check should still catch the modified @ record
        expect {
          described_class.call(operations, destination_with_modified_tracked, source, force: false)
        }.to raise_error(Zonesync::ChecksumMismatchError)
      end
    end
  end
end

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

    context "with multiple A records of same name" do
      # Hash for www A 3600 1.1.1.1 is v8lzoe
      # Hash for www A 3600 2.2.2.2 is 17pvyb4
      # Hash for www A 3600 3.3.3.3 is v5dbkl
      # Hash for www A 3600 4.4.4.4 is v5eixz

      context "when one of multiple A records is deleted" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          www               A     1.1.1.1
          www               A     2.2.2.2
          zonesync_manifest TXT   "v8lzoe,17pvyb4,v5dbkl"
        RECORDS

        let(:source_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          www  A  1.1.1.1
          www  A  2.2.2.2
          www  A  3.3.3.3
        RECORDS

        let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

        it "correctly identifies the deleted record, not another record with same name/type" do
          operations = []
          # Manifest tracks 3 www A records
          # Destination has only 2 (3.3.3.3 was deleted)
          # Should NOT show "Expected: 3.3.3.3, Actual: 1.1.1.1" - that would be wrong!
          # Should show that 3.3.3.3 was deleted
          expect {
            described_class.call(operations, destination, source, force: false)
          }.to raise_error(Zonesync::ChecksumMismatchError) do |error|
            expect(error.message).to eq(<<~MSG.chomp)
              The following tracked DNS record has been deleted externally:
                Expected: www.example.com. 3600 A 3.3.3.3 (hash: v5dbkl)
                Not found in current remote records.

              This probably means someone else has deleted it. Use --force to override.
            MSG
          end
        end
      end

      context "when one of multiple A records is replaced (deleted and different one added)" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          www               A     1.1.1.1
          www               A     2.2.2.2
          www               A     4.4.4.4
          zonesync_manifest TXT   "v8lzoe,17pvyb4,v5dbkl"
        RECORDS

        let(:source_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          www  A  1.1.1.1
          www  A  2.2.2.2
          www  A  3.3.3.3
        RECORDS

        let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

        it "correctly identifies this as a deletion, not a modification" do
          operations = []
          # Manifest tracks www A 3.3.3.3 (hash v5dbkl)
          # But destination has www A 4.4.4.4 instead (hash v5eixz)
          # These are NOT the same record - 3.3.3.3 was deleted and 4.4.4.4 was added
          # Should show deletion of 3.3.3.3, NOT "Expected: 3.3.3.3, Actual: 4.4.4.4"
          expect {
            described_class.call(operations, destination, source, force: false)
          }.to raise_error(Zonesync::ChecksumMismatchError) do |error|
            expect(error.message).to eq(<<~MSG.chomp)
              The following tracked DNS record has been deleted externally:
                Expected: www.example.com. 3600 A 3.3.3.3 (hash: v5dbkl)
                Not found in current remote records.

              This probably means someone else has deleted it. Use --force to override.
            MSG
          end
        end
      end
    end

    context "with corrupted/malformed manifest" do
      let(:source_records) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      RECORDS

      let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

      context "when manifest is empty" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   ""
        RECORDS

        it "does not raise error for empty manifest" do
          operations = []
          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "when manifest has trailing comma" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   "1r81el0,"
        RECORDS

        it "does not raise error or treat empty string as missing hash" do
          operations = []
          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "when manifest has multiple consecutive commas" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   "1r81el0,,,"
        RECORDS

        it "does not raise error or treat empty strings as missing hashes" do
          operations = []
          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "when manifest is just commas" do
        let(:destination_records) { <<~RECORDS }
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   ",,,"
        RECORDS

        it "does not raise error" do
          operations = []
          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end
    end

    context "v2 hash-based conflict detection when adding records" do
      let(:source) do
        zonefile = <<~RECORDS
          $ORIGIN example.com.
          $TTL 3600
          @     A     192.0.2.1
        RECORDS
        Zonesync::Provider.from({ provider: "Memory", string: zonefile })
      end

      context "CNAME conflicts" do
        it "should detect conflict when adding CNAME and untracked CNAME exists with same name" do
          # Remote has: www CNAME old.example.com (untracked)
          # Manifest tracks only @ A record
          # Local wants to add: www CNAME new.example.com
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            www               CNAME old.example.com.
            zonesync_manifest TXT   "1r81el0"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            www  CNAME new.example.com.
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          expect {
            described_class.call(operations, destination, source, force: false)
          }.to raise_error(Zonesync::ConflictError) do |error|
            expect(error.message).to include("www.example.com.")
            expect(error.message).to include("CNAME")
            expect(error.message).to include("old.example.com")
          end
        end

        it "should not conflict when adding CNAME and tracked CNAME exists with same name" do
          # Remote has: www CNAME old.example.com (tracked in manifest)
          # Local wants to change: www CNAME new.example.com
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            www               CNAME old.example.com.
            zonesync_manifest TXT   "1r81el0,11xobsr"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            www  CNAME new.example.com.
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          # Should propose change, not raise conflict error
          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "A record conflicts" do
        it "should not conflict when adding A record and untracked A record exists with same name" do
          # Remote has: www A 1.1.1.1 (untracked)
          # Local wants to add: www A 2.2.2.2
          # Multiple A records are allowed, so no conflict
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            www               A     1.1.1.1
            zonesync_manifest TXT   "1r81el0"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            www  A     2.2.2.2
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "MX record conflicts" do
        it "should detect conflict when adding MX with same name and same priority as untracked MX" do
          # Remote has: @ MX 10 mail.example.com (untracked)
          # Local wants to add: @ MX 10 mail2.example.com
          # Same priority = conflict
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            @                 MX    10 mail.example.com.
            zonesync_manifest TXT   "1r81el0"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            @    MX    10 mail2.example.com.
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          expect {
            described_class.call(operations, destination, source, force: false)
          }.to raise_error(Zonesync::ConflictError) do |error|
            expect(error.message).to include("example.com.")
            expect(error.message).to include("MX")
            expect(error.message).to include("10 mail.example.com")
          end
        end

        it "should not conflict when adding MX with same name but different priority than untracked MX" do
          # Remote has: @ MX 10 mail.example.com (untracked)
          # Local wants to add: @ MX 20 mail2.example.com
          # Different priority = no conflict
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            @                 MX    10 mail.example.com.
            zonesync_manifest TXT   "1r81el0"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            @    MX    20 mail2.example.com.
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end

      context "adding identical record" do
        it "should not conflict when adding exact duplicate of untracked record" do
          # Remote has: www A 1.1.1.1 (untracked)
          # Local wants to add: www A 1.1.1.1 (identical)
          # This means we just want to start tracking it
          remote_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @                 A     192.0.2.1
            www               A     1.1.1.1
            zonesync_manifest TXT   "1r81el0"
          RECORDS
          destination = Zonesync::Provider.from({ provider: "Memory", string: remote_zonefile })

          local_zonefile = <<~RECORDS
            $ORIGIN example.com.
            $TTL 3600
            @    A     192.0.2.1
            www  A     1.1.1.1
          RECORDS
          source = Zonesync::Provider.from({ provider: "Memory", string: local_zonefile })

          operations = destination.diff(source).call

          expect {
            described_class.call(operations, destination, source, force: false)
          }.not_to raise_error
        end
      end
    end
  end
end

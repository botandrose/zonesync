require "zonesync"

describe Zonesync::Sync do
  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

  context "with an existing manifest record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      ssh               A     192.0.2.1
      mail              A     192.0.2.3
      www               CNAME example.com.
      @                 MX    10 mail.example.com.
      @                 MX    20 mail2.example.com.
      zonesync_manifest TXT   "A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"
      zonesync_checksum TXT   "3edb50f5a72cdd0e93ee98a25efcc42340050732d62bdba67bf08426d2c3fe5e"
    RECORDS

    it "ignores manifest and checksum records if they match" do
      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          ssh  A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
        RECORDS
        destination,
      ).call
    end

    it "writes new manifest and checksum records if they don't match" do
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "example.com.",
          type: "MX",
          ttl: 3600,
          rdata: "30 mail3.example.com.",
          comment: nil,
        )
      )

      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20,@ 30"',
          comment: nil,
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"3edb50f5a72cdd0e93ee98a25efcc42340050732d62bdba67bf08426d2c3fe5e"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"c275d222d88edf019063f0b545e1b83fecce8dfdbea1ffcff09ebc39a3856025"',
          comment: nil,
        )
      )

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          ssh  A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
          @    MX    30 mail3.example.com.
        RECORDS
        destination,
      ).call
    end
  end

  context "with a manifest record and some additional records" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      ssh               A     192.0.2.1
      mail              A     192.0.2.3
      www               CNAME example.com.
      @                 MX    10 mail.example.com.
      @                 MX    20 mail2.example.com.
      zonesync_manifest TXT   "A:@,mail;CNAME:www;MX:@ 10"
      zonesync_checksum TXT   "733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"
    RECORDS

    it "ignores records that are not on the manifest" do
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "test.example.com.",
          type: "A",
          ttl: 3600,
          rdata: "192.0.2.4",
          comment: "new record",
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail;CNAME:www;MX:@ 10"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail,test;CNAME:www;MX:@ 10"',
          comment: nil,
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"900c4b3798a2c5dbedcf6609f1751a6934b1f236ddd5ec36a703273ff43cb223"',
          comment: nil,
        )
      )

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          test A     192.0.2.4 ; new record
          www  CNAME example.com.
          @    MX    10 mail.example.com.
        RECORDS
        destination,
      ).call
    end

    it "errors when there's a conflict between ignored records and new ones" do
      subject = described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail.example.com. ; conflict here
        RECORDS
        destination,
      )
      expect { subject.call }.to raise_error(Zonesync::ConflictError, <<~MSG)
        The following untracked DNS record already exists and would be overwritten.
          existing: example.com. 3600 MX 20 mail2.example.com.
          new:      example.com. 3600 MX 20 mail.example.com. ; conflict here
      MSG
    end

    it "allows new conflicting records to be added to the manifest when they match exactly" do
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "example.com.",
          type: "MX",
          ttl: 3600,
          rdata: "20 mail2.example.com.",
          comment: nil,
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail;CNAME:www;MX:@ 10"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail;CNAME:www;MX:@ 10,@ 20"',
          comment: nil,
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"5dd5b30dc05db772219c17a7c9716261fab54a54e038f6084728eef0b359a617"',
          comment: nil,
        )
      )

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
        RECORDS
        destination,
      ).call
    end
  end

  context "with an missing manifest record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      ssh               A     192.0.2.1
      mail              A     192.0.2.3
      www               CNAME example.com.
      @                 MX    10 mail.example.com.
      @                 MX    20 mail2.example.com.
    RECORDS

    it "errors when the applied changes don't match exactly" do
      subject = described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
        RECORDS
        destination,
      )
      expect { subject.call }.to raise_error(Zonesync::MissingManifestError, <<~MSG)
        The zonesync_manifest TXT record is missing. If this is the very first sync, make sure the Zonefile matches what's on the DNS server exactly. Otherwise, someone else may have removed it.
      MSG
    end

    it "allows an unchanged clone as an initial sync, and writes the manifest" do
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"',
          comment: nil,
        )
      )
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"3edb50f5a72cdd0e93ee98a25efcc42340050732d62bdba67bf08426d2c3fe5e"',
          comment: nil,
        )
      )

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          ssh  A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
        RECORDS
        destination,
      ).call
    end
  end

  context "with a mismatched checksum record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      ssh               A     192.0.2.1
      mail              A     192.0.2.3
      www               CNAME example.com.
      @                 MX    10 mail.example.com.
      @                 MX    20 mail2.example.com.
      zonesync_manifest TXT   "A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"
      zonesync_checksum TXT   "BADCHECKSUM"
    RECORDS

    it "errors" do
      subject = described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          ssh  A     192.0.2.1
          mail A     192.0.2.3
          www  CNAME example.com.
          @    MX    10 mail.example.com.
          @    MX    20 mail2.example.com.
        RECORDS
        destination,
      )
      expect { subject.call }.to raise_error(Zonesync::ChecksumMismatchError, <<~MSG)
        The zonesync_checksum TXT record does not match the current state of the DNS records. This probably means that someone else has changed them.
      MSG
    end
  end
end


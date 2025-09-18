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
      zonesync_manifest TXT   "1r81el0,60oib3,8a2s09,ky0g92,9pp0kg,1d71j6w"
      zonesync_checksum TXT   "e457cba2ded96c470f974b7060123dd66d6125375c61d7183a07a52a39ad5bf1"
    RECORDS

    it "removes legacy checksum when transitioning to v2 manifest" do
      # Mock the remove method since Memory provider doesn't implement it
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"e457cba2ded96c470f974b7060123dd66d6125375c61d7183a07a52a39ad5bf1"',
          comment: nil
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

    it "updates manifest and removes checksum when transitioning to v2" do
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
          rdata: '"1r81el0,60oib3,8a2s09,ky0g92,9pp0kg,1d71j6w"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,60oib3,8a2s09,ky0g92,9pp0kg,1d71j6w,1dtxj7k"',
          comment: nil,
        )
      )
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"e457cba2ded96c470f974b7060123dd66d6125375c61d7183a07a52a39ad5bf1"',
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
      zonesync_manifest TXT   "1r81el0,9pp0kg,60oib3,ky0g92"
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
          rdata: '"1r81el0,9pp0kg,60oib3,ky0g92"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,60oib3,1v0cfx0,ky0g92,9pp0kg"',
          comment: nil,
        )
      )
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"',
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


    it "allows a record to change type" do
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "www.example.com.",
          type: "CNAME",
          ttl: 3600,
          rdata: "example.com.",
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "www.example.com.",
          type: "A",
          ttl: 3600,
          rdata: "192.0.2.1",
          comment: nil,
        )
      )
      expect(destination).to receive(:change).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,9pp0kg,60oib3,ky0g92"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,60oib3,1rqeps,9pp0kg"',
          comment: nil,
        )
      )
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"',
          comment: nil,
        )
      )

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          www  A     192.0.2.1
          @    MX    10 mail.example.com.
        RECORDS
        destination,
      ).call
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
          rdata: '"1r81el0,9pp0kg,60oib3,ky0g92"',
          comment: nil,
        ),
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,60oib3,ky0g92,9pp0kg,1d71j6w"',
          comment: nil,
        )
      )
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"733dbb245b6465e831b3d78b7a3e1d315124b3317febcaf8918c111e07b9809c"',
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
      expect { subject.call }.to raise_error(Zonesync::MissingManifestError)
    end

    it "allows an unchanged clone as an initial sync, and writes the manifest" do
      expect(destination).to receive(:add).with(
        Zonesync::Record.new(
          name: "zonesync_manifest.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"1r81el0,60oib3,8a2s09,ky0g92,9pp0kg,1d71j6w"',
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
      zonesync_manifest TXT   "1r81el0,60oib3,8a2s09,ky0g92,9pp0kg,1d71j6w"
      zonesync_checksum TXT   "BADCHECKSUM"
    RECORDS

    it "removes legacy checksum when transitioning to v2" do
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"BADCHECKSUM"',
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

    it "succeeds with force flag" do
      expect(destination).to receive(:remove).with(
        Zonesync::Record.new(
          name: "zonesync_checksum.example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"BADCHECKSUM"',
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
      ).call(force: true)
    end
  end
end


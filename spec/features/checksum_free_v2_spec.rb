require "zonesync"

describe "Checksum-free v2 manifests" do
  let(:source_records) { <<~RECORDS }
    $ORIGIN example.com.
    $TTL 3600
    @    A     192.0.2.1
    mail A     192.0.2.3
  RECORDS

  let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

  context "with v2 manifest destination" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      mail              A     192.0.2.3
      zonesync_manifest TXT   "1r81el0,60oib3"
    RECORDS

    let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

    it "does not create or update checksum records for v2 manifests" do
      # Mock destination to capture what operations are attempted
      operations_performed = []
      allow(destination).to receive(:add) { |record| operations_performed << [:add, record] }
      allow(destination).to receive(:change) { |old, new| operations_performed << [:change, old, new] }
      allow(destination).to receive(:remove) { |record| operations_performed << [:remove, record] }

      Zonesync::Sync.new(source, destination).call

      # Should not perform any checksum operations
      checksum_operations = operations_performed.select do |op, *records|
        records.any? { |r| r.respond_to?(:checksum?) && r.checksum? }
      end

      expect(checksum_operations).to be_empty
    end
  end

  context "with v1 manifest destination" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      mail              A     192.0.2.3
      zonesync_manifest TXT   "A:@,mail"
      zonesync_checksum TXT   "oldchecksum"
    RECORDS

    let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

    it "removes checksum when source generates v2 manifest" do
      # Mock destination to capture what operations are attempted
      operations_performed = []
      allow(destination).to receive(:add) { |record| operations_performed << [:add, record] }
      allow(destination).to receive(:change) { |old, new| operations_performed << [:change, old, new] }
      allow(destination).to receive(:remove) { |record| operations_performed << [:remove, record] }

      # Need force=true because destination checksum is bad
      Zonesync::Sync.new(source, destination).call(force: true)

      # Should remove checksum when transitioning to v2
      checksum_removals = operations_performed.select do |op, *records|
        op == :remove && records.any? { |r| r.respond_to?(:checksum?) && r.checksum? }
      end

      expect(checksum_removals).not_to be_empty
    end
  end

  context "with both source and destination having v1 manifests" do
    let(:source_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @    A     192.0.2.1
      mail A     192.0.2.3
      zonesync_manifest TXT   "A:@,mail"
      zonesync_checksum TXT   "correctchecksum"
    RECORDS

    let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      mail              A     192.0.2.3
      zonesync_manifest TXT   "A:@,mail"
      zonesync_checksum TXT   "oldchecksum"
    RECORDS

    let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

    it "still syncs checksums for v1 to v1" do
      # Mock destination to capture what operations are attempted
      operations_performed = []
      allow(destination).to receive(:add) { |record| operations_performed << [:add, record] }
      allow(destination).to receive(:change) { |old, new| operations_performed << [:change, old, new] }
      allow(destination).to receive(:remove) { |record| operations_performed << [:remove, record] }

      # Both have v1 manifests, should sync checksum
      Zonesync::Sync.new(source, destination).call(force: true)

      # Should update checksum
      checksum_changes = operations_performed.select do |op, *records|
        op == :change && records.any? { |r| r.respond_to?(:checksum?) && r.checksum? }
      end

      expect(checksum_changes).not_to be_empty
    end
  end

  context "transitioning from v1 to v2" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 NS    ns.somewhere.example.
      @                 A     192.0.2.1
      mail              A     192.0.2.3
      zonesync_manifest TXT   "A:@,mail"
      zonesync_checksum TXT   "oldchecksum"
    RECORDS

    let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

    it "removes checksum record when upgrading from v1 to v2 manifest" do
      # Mock destination to capture what operations are attempted
      operations_performed = []
      allow(destination).to receive(:add) { |record| operations_performed << [:add, record] }
      allow(destination).to receive(:change) { |old, new| operations_performed << [:change, old, new] }
      allow(destination).to receive(:remove) { |record| operations_performed << [:remove, record] }

      # Source generates v2 manifest, destination has v1
      # Need force=true because destination checksum is bad
      Zonesync::Sync.new(source, destination).call(force: true)

      # Should remove the old checksum record
      checksum_removals = operations_performed.select do |op, *records|
        op == :remove && records.any? { |r| r.respond_to?(:checksum?) && r.checksum? }
      end

      expect(checksum_removals).not_to be_empty
    end
  end
end
require "zonesync"

describe Zonesync::Diff do
  describe ".call" do
    it "detects new records" do
      from = build(<<~RECORDS)
        @             A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             A     192.0.2.1             ; IPv4 address for example.com
        www           A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :add,
        [Zonesync::Record.new(
          type: "A",
          name: "www.example.com.",
          ttl: 3600,
          rdata: "192.0.2.1",
          comment: "IPv4 address for example.com",
        )]
      ]])
    end

    it "detects changed records" do
      from = build(<<~RECORDS)
        @             A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             A     10.0.0.1              ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :change,
        [
          Zonesync::Record.new(
            name: "example.com.",
            type: "A",
            ttl: 3600,
            rdata: "192.0.2.1",
            comment: "IPv4 address for example.com",
          ),
          Zonesync::Record.new(
            name: "example.com.",
            type: "A",
            ttl: 3600,
            rdata: "10.0.0.1",
            comment: "IPv4 address for example.com",
          ),
        ]
      ]])
    end

    it "ignores record reordering" do
      from = build(<<~RECORDS)
        @    A 10.0.0.1
        www  A 10.0.0.1
        test A 10.0.0.1
      RECORDS
      to = build(<<~RECORDS)
        @    A 10.0.0.1
        test A 10.0.0.1
        www  A 10.0.0.1
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([])
    end

    it "detects removed records" do
      from = build(<<~RECORDS)
        @             A     192.0.2.1             ; IPv4 address for example.com
        www           A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :remove,
        [Zonesync::Record.new(
          name: "www.example.com.",
          type: "A",
          ttl: 3600,
          rdata: "192.0.2.1",
          comment: "IPv4 address for example.com",
        )]
      ]])
    end

    it "does not treat record renames as changes" do
      # When record names change but rdata stays the same, these should be REMOVE + ADD
      # operations, NOT change operations. You can't "change" server1 into web1.
      from = build(<<~RECORDS)
        server1  A 1.2.3.4
        server2  A 1.2.3.4
        server3  A 1.2.3.4
      RECORDS
      to = build(<<~RECORDS)
        web1  A 1.2.3.4
        web2  A 1.2.3.4
        web3  A 1.2.3.4
      RECORDS

      ops = described_class.call(from: from, to: to)

      # Should be 3 removes + 3 adds, NOT 3 changes
      expect(ops).to contain_exactly(
        [:remove, [Zonesync::Record.new(name: "server1.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
        [:remove, [Zonesync::Record.new(name: "server2.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
        [:remove, [Zonesync::Record.new(name: "server3.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
        [:add, [Zonesync::Record.new(name: "web1.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
        [:add, [Zonesync::Record.new(name: "web2.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
        [:add, [Zonesync::Record.new(name: "web3.example.com.", type: "A", ttl: 3600, rdata: "1.2.3.4")]],
      )

      # Ensure NO operations incorrectly change names
      ops.each do |operation, records|
        if operation == :change
          expect(records[0].name).to eq(records[1].name),
            "CHANGE operations must keep the same name. Got: #{records[0].name} -> #{records[1].name}"
          expect(records[0].type).to eq(records[1].type),
            "CHANGE operations must keep the same type"
        end
      end
    end
  end
end

def build string
  Zonesync::Provider.from({ provider: "Memory", string: <<~STRING }).diffable_records
    $ORIGIN example.com.     ; designates the start of this zone file in the namespace
    $TTL 3600                ; default expiration time of all resource records without their own TTL value
    example.com.      SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
    #{string}
  STRING
end


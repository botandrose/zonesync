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
        [{
          type: "A",
          name: "www.example.com.",
          ttl: 3600,
          rdata: "192.0.2.1",
          comment: "IPv4 address for example.com",
        }]
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
          {
            name: "example.com.",
            type: "A",
            ttl: 3600,
            rdata: "192.0.2.1",
            comment: "IPv4 address for example.com",
          },
          {
            name: "example.com.",
            type: "A",
            ttl: 3600,
            rdata: "10.0.0.1",
            comment: "IPv4 address for example.com",
          },
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
        [{
          name: "www.example.com.",
          type: "A",
          ttl: 3600,
          rdata: "192.0.2.1",
          comment: "IPv4 address for example.com",
        }]
      ]])
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


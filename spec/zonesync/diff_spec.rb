require "zonesync"

describe Zonesync::Diff do
  describe ".call" do
    it "detects new records" do
      from = build(<<~RECORDS)
        @             IN  A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             IN  A     192.0.2.1             ; IPv4 address for example.com
        www           IN  A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :add,
        {
          type: "A",
          host: "www.example.com.",
          ttl: 3600,
          address: "192.0.2.1",
        }
      ]])
    end

    it "detects changed records" do
      from = build(<<~RECORDS)
        @             IN  A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             IN  A     10.0.0.1              ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :change,
        [
          {
            type: "A",
            host: "example.com.",
            ttl: 3600,
            address: "192.0.2.1",
          },
          {
            type: "A",
            host: "example.com.",
            ttl: 3600,
            address: "10.0.0.1",
          },
        ]
      ]])
    end

    it "detects removed records" do
      from = build(<<~RECORDS)
        @             IN  A     192.0.2.1             ; IPv4 address for example.com
        www           IN  A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      to = build(<<~RECORDS)
        @             IN  A     192.0.2.1             ; IPv4 address for example.com
      RECORDS
      ops = described_class.call(from: from, to: to)
      expect(ops).to eq([[
        :remove,
        {
          type: "A",
          host: "www.example.com.",
          ttl: 3600,
          address: "192.0.2.1",
        }
      ]])
    end
  end
end

def build string
  Zonesync::Provider.new({ provider: "Memory", string: <<~STRING })
    $ORIGIN example.com.     ; designates the start of this zone file in the namespace
    $TTL 3600                ; default expiration time of all resource records without their own TTL value
    example.com.  IN  SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
    #{string}
  STRING
end


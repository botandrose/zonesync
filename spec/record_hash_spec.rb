require "zonesync"

describe Zonesync::RecordHash do
  describe ".generate" do
    it "generates expected hash for A record" do
      record = Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      hash = described_class.generate(record)

      expect(hash).to eq("1r81el0")
    end

    it "generates expected hash for TXT record" do
      record = Zonesync::Record.new(
        name: "example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
        comment: nil
      )

      hash = described_class.generate(record)

      expect(hash).to eq("td1ulz")
    end

    it "generates different hashes for different IP addresses" do
      record1 = Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      record2 = Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.2",
        comment: nil
      )

      expect(described_class.generate(record1)).to eq("1r81el0")
      expect(described_class.generate(record2)).to eq("y2xy9a")
    end
  end
end
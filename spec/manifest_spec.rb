require "zonesync"

describe Zonesync::Manifest do
  let(:zone) { double("zone", origin: "example.com.") }
  let(:records) do
    [
      Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
      Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil),
      Zonesync::Record.new(name: "example.com.", type: "TXT", ttl: 3600, rdata: '"v=spf1 include:spf.protection.outlook.com -all"', comment: nil),
      Zonesync::Record.new(name: "www.example.com.", type: "CNAME", ttl: 3600, rdata: "example.com.", comment: nil)
    ]
  end
  let(:manifest) { described_class.new(records, zone) }

  describe "#generate" do
    it "generates hash-based manifest format (switched to v2)" do
      result = manifest.generate

      expect(result.name).to eq("zonesync_manifest.example.com.")
      expect(result.type).to eq("TXT")
      expect(result.ttl).to eq(3600)
      expect(result.rdata).to eq('"1r81el0,y2xy9a,ky0g92,td1ulz"')
      expect(result.comment).to be_nil
    end
  end

  describe "#generate_v2" do
    it "generates hash-based manifest" do
      result = manifest.generate_v2

      expect(result.name).to eq("zonesync_manifest.example.com.")
      expect(result.type).to eq("TXT")
      expect(result.ttl).to eq(3600)
      expect(result.rdata).to eq('"1r81el0,y2xy9a,ky0g92,td1ulz"')
      expect(result.comment).to be_nil
    end

    it "includes only diffable records" do
      soa_record = Zonesync::Record.new(name: "example.com.", type: "SOA", ttl: 3600, rdata: "ns.example.com. admin.example.com. 1 3600 1800 604800 86400", comment: nil)
      all_records = records + [soa_record]
      manifest_with_soa = described_class.new(all_records, zone)

      result = manifest_with_soa.generate_v2

      expect(result.rdata).to eq('"1r81el0,y2xy9a,ky0g92,td1ulz"')
    end

    it "orders hashes consistently by record sort order" do
      reversed_records = records.reverse
      reversed_manifest = described_class.new(reversed_records, zone)

      result = reversed_manifest.generate_v2

      expect(result.rdata).to eq('"1r81el0,y2xy9a,ky0g92,td1ulz"')
    end
  end
end
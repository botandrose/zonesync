require "zonesync"

describe Zonesync::Provider do
  describe "#diffable_records" do
    let(:credentials) { { provider: "Filesystem", path: zonefile_path } }
    subject { described_class.from(credentials) }

    context "with a full zonefile" do
      let(:zonefile_path) { './spec/fixtures/example.com' }

      it "returns all records minus SOA and NS" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. A 3 192.0.2.1",
          "mail.example.com. A 3 192.0.2.3",
          "mail2.example.com. A 3 192.0.2.4",
          "mail3.example.com. A 3 192.0.2.5",
          "ns.example.com. A 3 192.0.2.2",
          "example.com. AAAA 3 2001:db8:10::1",
          "ns.example.com. AAAA 3 2001:db8:10::2",
          "www.example.com. CNAME 3 example.com.",
          "wwwtest.example.com. CNAME 3 www.example.com.",
          "example.com. MX 3 10 mail.example.com.",
          "example.com. MX 3 20 mail2.example.com.",
          "example.com. MX 3 50 mail3.example.com.",
        ])
      end
    end

    context "with a partial zonefile missing SOA and NS records" do
      let(:zonefile_path) { './spec/fixtures/example.com-without_unsyncable_records' }

      it "returns all records" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. A 3 192.0.2.1",
          "mail.example.com. A 3 192.0.2.3",
          "mail2.example.com. A 3 192.0.2.4",
          "mail3.example.com. A 3 192.0.2.5",
          "ns.example.com. A 3 192.0.2.2",
          "example.com. AAAA 3 2001:db8:10::1",
          "ns.example.com. AAAA 3 2001:db8:10::2",
          "www.example.com. CNAME 3 example.com.",
          "wwwtest.example.com. CNAME 3 www.example.com.",
          "example.com. MX 3 10 mail.example.com.",
          "example.com. MX 3 20 mail2.example.com.",
          "example.com. MX 3 50 mail3.example.com.",
        ])
      end
    end
  end
end


require "zonesync"

describe Zonesync::Provider do
  describe "#diffable_records" do
    let(:credentials) { { provider: "Filesystem", path: zonefile_path } }
    subject { described_class.from(credentials) }

    context "with a full zonefile" do
      let(:zonefile_path) { './spec/fixtures/example.com' }

      it "returns all records minus SOA and NS" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. A 3 192.0.2.1 ; IPv4 address for example.com",
          "mail.example.com. A 3 192.0.2.3 ; IPv4 address for mail.example.com",
          "mail2.example.com. A 3 192.0.2.4 ; IPv4 address for mail2.example.com",
          "mail3.example.com. A 3 192.0.2.5 ; IPv4 address for mail3.example.com",
          "ns.example.com. A 3 192.0.2.2 ; IPv4 address for ns.example.com",
          "example.com. AAAA 3 2001:db8:10::1 ; IPv6 address for example.com",
          "ns.example.com. AAAA 3 2001:db8:10::2 ; IPv6 address for ns.example.com",
          "www.example.com. CNAME 3 example.com. ; www.example.com is an alias for example.com",
          "wwwtest.example.com. CNAME 3 www.example.com. ; wwwtest.example.com is another alias for www.example.com",
          "example.com. MX 3 10 mail.example.com. ; mail.example.com is the mailserver for example.com",
          "example.com. MX 3 20 mail2.example.com. ; equivalent to above line, \"@\" represents zone origin",
          "example.com. MX 3 50 mail3.example.com. ; equivalent to above line, but using a relative host name",
        ])
      end
    end

    context "with a partial zonefile missing SOA and NS records" do
      let(:zonefile_path) { './spec/fixtures/example.com-without_unsyncable_records' }

      it "returns all records" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. A 3 192.0.2.1 ; IPv4 address for example.com",
          "mail.example.com. A 3 192.0.2.3 ; IPv4 address for mail.example.com",
          "mail2.example.com. A 3 192.0.2.4 ; IPv4 address for mail2.example.com",
          "mail3.example.com. A 3 192.0.2.5 ; IPv4 address for mail3.example.com",
          "ns.example.com. A 3 192.0.2.2 ; IPv4 address for ns.example.com",
          "example.com. AAAA 3 2001:db8:10::1 ; IPv6 address for example.com",
          "ns.example.com. AAAA 3 2001:db8:10::2 ; IPv6 address for ns.example.com",
          "www.example.com. CNAME 3 example.com. ; www.example.com is an alias for example.com",
          "wwwtest.example.com. CNAME 3 www.example.com. ; wwwtest.example.com is another alias for www.example.com",
          "example.com. MX 3 10 mail.example.com. ; mail.example.com is the mailserver for example.com",
          "example.com. MX 3 20 mail2.example.com. ; equivalent to above line, \"@\" represents zone origin",
          "example.com. MX 3 50 mail3.example.com. ; equivalent to above line, but using a relative host name",
        ])
      end
    end
  end
end


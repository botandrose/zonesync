require "zonesync"

describe Zonesync::Provider do
  describe "#diffable_records" do
    let(:credentials) { { provider: "Filesystem", path: zonefile_path } }
    subject { described_class.from(credentials) }

    context "with a full zonefile" do
      let(:zonefile_path) { './spec/fixtures/example.com' }

      it "returns all records minus SOA and NS" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. 3600 A 192.0.2.1 ; IPv4 address for example.com",
          "mail.example.com. 3600 A 192.0.2.3 ; IPv4 address for mail.example.com",
          "mail2.example.com. 3600 A 192.0.2.4 ; IPv4 address for mail2.example.com",
          "mail3.example.com. 3600 A 192.0.2.5 ; IPv4 address for mail3.example.com",
          "ns.example.com. 3600 A 192.0.2.2 ; IPv4 address for ns.example.com",
          "example.com. 3600 AAAA 2001:db8:10::1 ; IPv6 address for example.com",
          "ns.example.com. 3600 AAAA 2001:db8:10::2 ; IPv6 address for ns.example.com",
          "www.example.com. 3600 CNAME example.com. ; www.example.com is an alias for example.com",
          "wwwtest.example.com. 3600 CNAME www.example.com. ; wwwtest.example.com is another alias for www.example.com",
          "example.com. 3600 MX 10 mail.example.com. ; mail.example.com is the mailserver for example.com",
          "example.com. 3600 MX 20 mail2.example.com. ; equivalent to above line, \"@\" represents zone origin",
          "example.com. 3600 MX 50 mail3.example.com. ; equivalent to above line, but using a relative host name",
        ])
      end
    end

    context "with a partial zonefile missing SOA and NS records" do
      let(:zonefile_path) { './spec/fixtures/example.com-without_unsyncable_records' }

      it "returns all records" do
        expect(subject.diffable_records.map(&:to_s)).to eq([
          "example.com. 3600 A 192.0.2.1 ; IPv4 address for example.com",
          "mail.example.com. 3600 A 192.0.2.3 ; IPv4 address for mail.example.com",
          "mail2.example.com. 3600 A 192.0.2.4 ; IPv4 address for mail2.example.com",
          "mail3.example.com. 3600 A 192.0.2.5 ; IPv4 address for mail3.example.com",
          "ns.example.com. 3600 A 192.0.2.2 ; IPv4 address for ns.example.com",
          "example.com. 3600 AAAA 2001:db8:10::1 ; IPv6 address for example.com",
          "ns.example.com. 3600 AAAA 2001:db8:10::2 ; IPv6 address for ns.example.com",
          "www.example.com. 3600 CNAME example.com. ; www.example.com is an alias for example.com",
          "wwwtest.example.com. 3600 CNAME www.example.com. ; wwwtest.example.com is another alias for www.example.com",
          "example.com. 3600 MX 10 mail.example.com. ; mail.example.com is the mailserver for example.com",
          "example.com. 3600 MX 20 mail2.example.com. ; equivalent to above line, \"@\" represents zone origin",
          "example.com. 3600 MX 50 mail3.example.com. ; equivalent to above line, but using a relative host name",
        ])
      end
    end
  end

  context "#diffable_records with hash-based manifests" do
    let(:provider) { Zonesync::Provider.from({ provider: "Memory", string: records_string }) }

    context "with v2 hash-based manifest" do
      let(:records_string) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 NS    ns.somewhere.example.
        @                 A     192.0.2.1
        @                 TXT   "v=spf1 include:spf.protection.outlook.com -all"
        @                 TXT   "google-site-verification=abc123"
        zonesync_manifest TXT   "1r81el0,1t3k99e,td1ulz"
      RECORDS

      it "uses hash-based conflict detection to distinguish between different TXT records" do
        # The manifest contains hashes for: A record + 2 specific TXT records
        # This should recognize both TXT records as managed, even though they have the same name

        diffable = provider.diffable_records

        # Should find all 3 managed records: 1 A record + 2 TXT records
        expect(diffable.length).to eq(3)

        # Should include both TXT records
        txt_records = diffable.select { |r| r.type == "TXT" && !r.manifest? }
        expect(txt_records.length).to eq(2)

        # Should include the A record
        a_records = diffable.select { |r| r.type == "A" }
        expect(a_records.length).to eq(1)
      end

      it "excludes unmanaged TXT records when using hash-based detection" do
        records_with_extra = <<~RECORDS
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 NS    ns.somewhere.example.
          @                 A     192.0.2.1
          @                 TXT   "v=spf1 include:spf.protection.outlook.com -all"
          @                 TXT   "google-site-verification=abc123"
          @                 TXT   "unmanaged-record=xyz789"
          zonesync_manifest TXT   "1r81el0,1t3k99e,td1ulz"
        RECORDS

        provider_with_extra = Zonesync::Provider.from({ provider: "Memory", string: records_with_extra })
        diffable = provider_with_extra.diffable_records

        # Should still find only the 3 managed records, excluding the unmanaged TXT record
        expect(diffable.length).to eq(3)

        # Should only include the 2 managed TXT records, not the unmanaged one
        txt_records = diffable.select { |r| r.type == "TXT" && !r.manifest? }
        expect(txt_records.length).to eq(2)

        # The unmanaged TXT record should not be included
        unmanaged_txt = diffable.find { |r| r.rdata.include?("unmanaged-record") }
        expect(unmanaged_txt).to be_nil
      end
    end

    context "with v1 name-based manifest (backward compatibility)" do
      let(:records_string) { <<~RECORDS }
        $ORIGIN example.com.
        $TTL 3600
        @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
        @                 NS    ns.somewhere.example.
        @                 A     192.0.2.1
        @                 TXT   "v=spf1 include:spf.protection.outlook.com -all"
        zonesync_manifest TXT   "A:@;TXT:@"
      RECORDS

      it "still uses name-based conflict detection for v1 manifests" do
        diffable = provider.diffable_records

        # Should find 2 managed records: A record + TXT record
        expect(diffable.length).to eq(2)

        # Should include the TXT record
        txt_records = diffable.select { |r| r.type == "TXT" && !r.manifest? }
        expect(txt_records.length).to eq(1)
      end
    end

    context "real-world scenario: zone with no manifest" do
      let(:records_string) { <<~RECORDS }
        $ORIGIN filmpreservation.org.
        $TTL 3600
        @                 SOA   ns1.dreamhost.com. hostmaster.dreamhost.com. ( 2024010101 14400 3600 1209600 14400 )
        @                 NS    ns1.dreamhost.com.
        @                 NS    ns2.dreamhost.com.
        @                 A     64.90.62.230
        @                 TXT   "v=spf1 include:spf.protection.outlook.com include:networkforgood.com include:networkforgood.org -all"
      RECORDS

      it "should not conflict when adding a different TXT record with --force" do
        # This simulates the real-world scenario you encountered
        # The zone has an SPF TXT record, but no manifest
        # We want to add a Google site verification TXT record
        # These should not conflict because they are different TXT records

        diffable = provider.diffable_records

        # With no manifest, all diffable record types should be included
        expect(diffable.length).to eq(2) # A record + existing TXT record

        # The existing TXT record should be diffable
        txt_records = diffable.select { |r| r.type == "TXT" }
        expect(txt_records.length).to eq(1)
        expect(txt_records.first.rdata).to include("v=spf1")
      end
    end
  end

  describe "#hash_based_diffable_records" do
    let(:provider) { Zonesync::Provider.from({ provider: "Memory", string: "" }) }

    it "returns matching records when all hashes are found" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil),
        Zonesync::Record.new(name: "mail.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.3", comment: nil)
      ]

      expected_hashes = ["1r81el0", "y2xy9a"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result).to contain_exactly(
        remote_records[0],
        remote_records[1]
      )
    end

    it "ignores unmanaged records" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
        Zonesync::Record.new(name: "unmanaged.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.99", comment: nil)
      ]

      expected_hashes = ["1r81el0"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result).to contain_exactly(remote_records[0])
    end

    it "raises ConflictError when managed records are missing" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil)
      ]

      expected_hashes = ["1r81el0", "y2xy9a"]

      expect {
        provider.send(:hash_based_diffable_records, remote_records, expected_hashes)
      }.to raise_error(Zonesync::ConflictError)
    end

    it "raises ConflictError when managed record has been changed remotely" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.99", comment: nil)
      ]

      expected_hashes = ["1r81el0"]

      expect {
        provider.send(:hash_based_diffable_records, remote_records, expected_hashes)
      }.to raise_error(Zonesync::ConflictError)
    end

    it "sorts the returned records" do
      remote_records = [
        Zonesync::Record.new(name: "zzz.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil),
        Zonesync::Record.new(name: "aaa.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil)
      ]

      expected_hashes = ["hoeh05", "1w6mrp4"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result[0].name).to eq("aaa.example.com.")
      expect(result[1].name).to eq("zzz.example.com.")
    end
  end
end


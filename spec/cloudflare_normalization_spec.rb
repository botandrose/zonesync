require "zonesync"

describe Zonesync::Cloudflare do
  context "TXT record normalization" do
    it "handles multi-part TXT records from CloudFlare API" do
      # Mock the HTTP client to return CloudFlare's multi-part TXT record format
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      # CloudFlare returns long TXT records split into multiple quoted parts
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "1234",
            "name" => "cf2024-1._domainkey.example.com",
            "type" => "TXT",
            "content" => "\"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78k\" \"m4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB\"",
            "ttl" => 1,
            "comment" => nil
          }
        ]
      })

      config = {
        provider: "Cloudflare",
        zone_id: "test_zone",
        token: "test_token"
      }

      cloudflare = described_class.new(config)
      allow(cloudflare).to receive(:http).and_return(http_client)

      records = cloudflare.all.keys
      dkim_record = records.find { |r| r.name.include?("cf2024-1._domainkey") }

      # The normalized record should have the complete DKIM key as a single quoted string
      expected_content = "\"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78km4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB\""

      expect(dkim_record.rdata).to eq(expected_content)
    end

    it "recognizes identical TXT records despite CloudFlare's multi-part format" do
      # Source record (from Zonefile)
      source_record = Zonesync::Record.new(
        name: "cf2024-1._domainkey.example.com.",
        type: "TXT",
        ttl: 1,
        rdata: "\"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78km4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB\"",
        comment: nil
      )

      # Mock CloudFlare provider with multi-part TXT record
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "1234",
            "name" => "cf2024-1._domainkey.example.com",
            "type" => "TXT",
            "content" => "\"v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAiweykoi+o48IOGuP7GR3X0MOExCUDY/BCRHoWBnh3rChl7WhdyCxW3jgq1daEjPPqoi7sJvdg5hEQVsgVRQP4DcnQDVjGMbASQtrY4WmB1VebF+RPJB2ECPsEDTpeiI5ZyUAwJaVX7r6bznU67g7LvFq35yIo4sdlmtZGV+i0H4cpYH9+3JJ78k\" \"m4KXwaf9xUJCWF6nxeD+qG6Fyruw1Qlbds2r85U9dkNDVAS3gioCvELryh1TxKGiVTkg4wqHTyHfWsp7KD3WQHYJn0RyfJJu6YEmL77zonn7p2SRMvTMP3ZEXibnC9gz3nnhR6wcYL8Q7zXypKTMD58bTixDSJwIDAQAB\"",
            "ttl" => 1,
            "comment" => nil
          }
        ]
      })

      config = {
        provider: "Cloudflare",
        zone_id: "test_zone",
        token: "test_token"
      }

      cloudflare = described_class.new(config)
      allow(cloudflare).to receive(:http).and_return(http_client)

      cloudflare_records = cloudflare.all.keys
      dkim_record = cloudflare_records.find { |r| r.name.include?("cf2024-1._domainkey") }

      # These should be equal - the diff algorithm should not try to add the record
      expect(source_record).to eq(dkim_record)
    end
  end

  context "MX record handling" do
    it "includes MX records in CloudFlare API response" do
      # Mock the HTTP client to return MX records
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      # CloudFlare should return MX records in the API response
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "mx1",
            "name" => "example.com",
            "type" => "MX",
            "content" => "route1.mx.cloudflare.net",
            "priority" => 33,
            "ttl" => 1,
            "comment" => nil
          },
          {
            "id" => "mx2",
            "name" => "example.com",
            "type" => "MX",
            "content" => "route2.mx.cloudflare.net",
            "priority" => 90,
            "ttl" => 1,
            "comment" => nil
          },
          {
            "id" => "mx3",
            "name" => "mail.example.com",
            "type" => "MX",
            "content" => "mail.example.com",
            "priority" => 10,
            "ttl" => 1,
            "comment" => nil
          }
        ]
      })

      config = {
        provider: "Cloudflare",
        zone_id: "test_zone",
        token: "test_token"
      }

      cloudflare = described_class.new(config)
      allow(cloudflare).to receive(:http).and_return(http_client)

      records = cloudflare.all.keys
      mx_records = records.select { |r| r.type == "MX" }

      expect(mx_records.length).to eq(3)

      # Check that MX records are properly normalized
      route1_mx = mx_records.find { |r| r.rdata.include?("route1.mx.cloudflare.net") }
      expect(route1_mx.rdata).to eq("33 route1.mx.cloudflare.net.")

      mail_mx = mx_records.find { |r| r.name.include?("mail.") }
      expect(mail_mx.rdata).to eq("10 mail.example.com.")
    end

    it "does not try to add MX records that already exist" do
      # Source records (from Zonefile)
      source_records = [
        Zonesync::Record.new(
          name: "example.com.",
          type: "MX",
          ttl: 1,
          rdata: "33 route1.mx.cloudflare.net.",
          comment: nil
        ),
        Zonesync::Record.new(
          name: "mail.example.com.",
          type: "MX",
          ttl: 1,
          rdata: "10 mail.example.com.",
          comment: nil
        )
      ]

      # Mock CloudFlare provider with the same MX records
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "mx1",
            "name" => "example.com",
            "type" => "MX",
            "content" => "route1.mx.cloudflare.net",
            "priority" => 33,
            "ttl" => 1,
            "comment" => nil
          },
          {
            "id" => "mx2",
            "name" => "mail.example.com",
            "type" => "MX",
            "content" => "mail.example.com",
            "priority" => 10,
            "ttl" => 1,
            "comment" => nil
          }
        ]
      })

      config = {
        provider: "Cloudflare",
        zone_id: "test_zone",
        token: "test_token"
      }

      cloudflare = described_class.new(config)
      allow(cloudflare).to receive(:http).and_return(http_client)

      cloudflare_records = cloudflare.all.keys

      # The MX records should match exactly
      source_records.each do |source_record|
        matching_record = cloudflare_records.find { |cf_record|
          cf_record.name == source_record.name &&
          cf_record.type == source_record.type &&
          cf_record.rdata == source_record.rdata
        }
        expect(matching_record).not_to be_nil, "Could not find matching record for #{source_record}"
      end
    end
  end

  context "MX record to_hash conversion" do
    it "splits MX record rdata into priority and content fields for CloudFlare API" do
      # Create an MX record as zonesync would parse from Zonefile
      mx_record = Zonesync::Record.new(
        name: "example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "10 mail.example.com.",
        comment: nil
      )

      cloudflare = described_class.new({})
      result_hash = cloudflare.send(:to_hash, mx_record)

      # CloudFlare API expects priority as integer and content without priority
      expect(result_hash[:priority]).to eq(10)
      expect(result_hash[:content]).to eq("mail.example.com")
      expect(result_hash[:type]).to eq("MX")
      expect(result_hash[:name]).to eq("example.com.")
      expect(result_hash[:ttl]).to eq(3600)
    end

    it "handles MX records with trailing dots in hostname" do
      mx_record = Zonesync::Record.new(
        name: "bardtracker.com.",
        type: "MX",
        ttl: 1,
        rdata: "33 route1.mx.cloudflare.net.",
        comment: nil
      )

      cloudflare = described_class.new({})
      result_hash = cloudflare.send(:to_hash, mx_record)

      # Should remove trailing dot from hostname
      expect(result_hash[:priority]).to eq(33)
      expect(result_hash[:content]).to eq("route1.mx.cloudflare.net")
    end

    it "does not affect non-MX records" do
      # Test that regular records still work correctly
      a_record = Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      cloudflare = described_class.new({})
      result_hash = cloudflare.send(:to_hash, a_record)

      # A records should have content, not priority
      expect(result_hash[:content]).to eq("192.0.2.1")
      expect(result_hash[:priority]).to be_nil
      expect(result_hash[:type]).to eq("A")
    end
  end
end

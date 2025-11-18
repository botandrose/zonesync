require "zonesync"

describe "Cloudflare proxied status support" do
  context "reading proxied status from Cloudflare API" do
    it "includes cf_tags=cf-proxied in zone file output" do
      # Mock the HTTP client to return records with proxied status
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "1",
            "name" => "example.com",
            "type" => "A",
            "content" => "192.0.2.1",
            "ttl" => 3600,
            "proxied" => true,
            "comment" => "Proxied record"
          },
          {
            "id" => "2",
            "name" => "mail.example.com",
            "type" => "A",
            "content" => "192.0.2.2",
            "ttl" => 3600,
            "proxied" => false,
            "comment" => "DNS-only record"
          },
          {
            "id" => "3",
            "name" => "www.example.com",
            "type" => "CNAME",
            "content" => "example.com",
            "ttl" => 3600,
            "proxied" => true,
            "comment" => nil
          }
        ]
      })

      config = {
        provider: "Cloudflare",
        zone_id: "test_zone",
        token: "test_token"
      }

      cloudflare = Zonesync::Cloudflare.new(config)
      allow(cloudflare).to receive(:http).and_return(http_client)

      zone_file = cloudflare.read

      # Verify the zone file contains cf_tags with proxied status
      expect(zone_file).to include("cf_tags=cf-proxied:true")
      expect(zone_file).to include("cf_tags=cf-proxied:false")

      # Verify the records are in the zone file with correct format
      expect(zone_file).to match(/example\.com\. 3600 A 192\.0\.2\.1 ; cf_tags=cf-proxied:true Proxied record/)
      expect(zone_file).to match(/mail\.example\.com\. 3600 A 192\.0\.2\.2 ; cf_tags=cf-proxied:false DNS-only record/)
      expect(zone_file).to match(/www\.example\.com\. 3600 CNAME example\.com\. ; cf_tags=cf-proxied:true/)
    end
  end

  context "parsing cf_tags from zone files" do
    it "extracts proxied status from cf_tags comments" do
      zone_file = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        example.com. 1 SOA ns.example.com. admin.example.com. 2000010101 1 1 1 1
        www          IN A     192.0.2.1 ; cf_tags=cf-proxied:true
        mail         IN A     192.0.2.2 ; cf_tags=cf-proxied:false
        api          IN A     192.0.2.3 ; Regular comment without cf_tags
      ZONEFILE

      zonefile = Zonesync::Zonefile.load(zone_file)

      www_record = zonefile.records.find { |r| r.name == "www.example.com." }
      mail_record = zonefile.records.find { |r| r.name == "mail.example.com." }
      api_record = zonefile.records.find { |r| r.name == "api.example.com." }

      expect(www_record.proxied).to eq(true)
      expect(mail_record.proxied).to eq(false)
      expect(api_record.proxied).to be_nil
    end
  end

  context "sending proxied status to Cloudflare API" do
    it "includes proxied field in API requests when set" do
      http_client = double("HTTP")

      # Expect POST request with proxied: true
      expect(http_client).to receive(:post).with("", hash_including(
        name: "www.example.com.",
        type: "A",
        content: "192.0.2.1",
        proxied: true
      )).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      record = Zonesync::Record.new(
        name: "www.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil,
        proxied: true
      )

      cloudflare.add(record)
    end

    it "includes proxied field in PATCH requests when updating records" do
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "123",
            "name" => "www.example.com",
            "type" => "A",
            "content" => "192.0.2.1",
            "ttl" => 3600,
            "proxied" => false
          }
        ]
      })

      # Expect PATCH request with proxied: true
      expect(http_client).to receive(:patch).with("/123", hash_including(
        proxied: true
      )).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      old_record = Zonesync::Record.new(
        name: "www.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        proxied: false
      )

      new_record = Zonesync::Record.new(
        name: "www.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        proxied: true
      )

      cloudflare.change(old_record, new_record)
    end

    it "does not include proxied field when nil" do
      http_client = double("HTTP")

      # Expect POST request WITHOUT proxied field
      expect(http_client).to receive(:post).with("", hash_excluding(:proxied)).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      record = Zonesync::Record.new(
        name: "mail.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.2",
        comment: nil,
        proxied: nil
      )

      cloudflare.add(record)
    end
  end

  context "end-to-end proxy status sync" do
    it "syncs proxy status changes from zone file to Cloudflare" do
      # Setup: Zone file wants to enable proxy for www record
      zone_file = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        example.com. 1 SOA ns.example.com. admin.example.com. 2000010101 1 1 1 1
        www          IN A     192.0.2.1 ; cf_tags=cf-proxied:true
      ZONEFILE

      # Mock Cloudflare API showing record currently not proxied
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "123",
            "name" => "www.example.com",
            "type" => "A",
            "content" => "192.0.2.1",
            "ttl" => 3600,
            "proxied" => false
          }
        ]
      })

      # Expect update to enable proxy
      expect(http_client).to receive(:patch).with("/123", hash_including(
        proxied: true
      )).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      # Load zone file
      zonefile = Zonesync::Zonefile.load(zone_file)
      source_record = zonefile.records.find { |r| r.name == "www.example.com." }

      # Verify source record has proxied=true
      expect(source_record.proxied).to eq(true)

      # Get existing record from Cloudflare
      existing_records = cloudflare.all
      existing_record = existing_records.keys.find { |r| r.name == "www.example.com." }

      # Verify existing record has proxied=false
      expect(existing_record.proxied).to eq(false)

      # Perform the change
      cloudflare.change(existing_record, source_record)
    end
  end

  context "preserving existing comments with cf_tags" do
    it "combines cf_tags with existing comments" do
      zone_file = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        example.com. 1 SOA ns.example.com. admin.example.com. 2000010101 1 1 1 1
        www          IN A     192.0.2.1
      ZONEFILE

      # Mock Cloudflare returning record with comment
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          {
            "id" => "1",
            "name" => "www.example.com",
            "type" => "A",
            "content" => "192.0.2.1",
            "ttl" => 3600,
            "proxied" => true,
            "comment" => "Important web server"
          }
        ]
      })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      zone_file_output = cloudflare.read

      # Should have both cf_tags and the original comment
      expect(zone_file_output).to match(/www\.example\.com\. 3600 A 192\.0\.2\.1 ; cf_tags=cf-proxied:true Important web server/)
    end
  end
end

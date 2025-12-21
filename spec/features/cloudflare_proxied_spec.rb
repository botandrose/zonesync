require "zonesync"

describe "Cloudflare proxied status support" do
  context "reading proxied status from Cloudflare API" do
    it "includes cf_tags=cf-proxied:true only for proxied records" do
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({
        "result" => { "name" => "example.com" }
      })

      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          { "id" => "1", "name" => "example.com", "type" => "A", "content" => "192.0.2.1", "ttl" => 3600, "proxied" => true, "comment" => "Proxied record" },
          { "id" => "2", "name" => "mail.example.com", "type" => "A", "content" => "192.0.2.2", "ttl" => 3600, "proxied" => false, "comment" => "DNS-only record" },
          { "id" => "3", "name" => "www.example.com", "type" => "CNAME", "content" => "example.com", "ttl" => 3600, "proxied" => true, "comment" => nil }
        ]
      })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      zone_file = cloudflare.read

      expect(zone_file).to include("cf_tags=cf-proxied:true")
      expect(zone_file).not_to include("cf_tags=cf-proxied:false")
      expect(zone_file).to match(/example\.com\. 3600 A 192\.0\.2\.1 ; cf_tags=cf-proxied:true Proxied record/)
      expect(zone_file).to match(/mail\.example\.com\. 3600 A 192\.0\.2\.2 ; DNS-only record/)
      expect(zone_file).to match(/www\.example\.com\. 3600 CNAME example\.com\. ; cf_tags=cf-proxied:true/)
    end
  end

  context "parsing cf_tags from zone files" do
    it "extracts proxied status from cf_tags comments via Cloudflare adapter" do
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
      www_record.extend(Zonesync::Cloudflare::ProxiedSupport)
      expect(www_record.proxied).to eq(true)
      expect(www_record.comment).to be_nil

      mail_record = zonefile.records.find { |r| r.name == "mail.example.com." }
      mail_record.extend(Zonesync::Cloudflare::ProxiedSupport)
      expect(mail_record.proxied).to eq(false)

      api_record = zonefile.records.find { |r| r.name == "api.example.com." }
      api_record.extend(Zonesync::Cloudflare::ProxiedSupport)
      expect(api_record.proxied).to be_nil
      expect(api_record.comment).to eq("Regular comment without cf_tags")
    end

    it "does not mutate the original record" do
      zone_file = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        example.com. 1 SOA ns.example.com. admin.example.com. 2000010101 1 1 1 1
        www          IN A     192.0.2.1 ; cf_tags=cf-proxied:true
      ZONEFILE

      zonefile = Zonesync::Zonefile.load(zone_file)
      record = zonefile.records.find { |r| r.name == "www.example.com." }
      original_comment = record.comment

      record.extend(Zonesync::Cloudflare::ProxiedSupport)

      # Comment is now parsed to strip cf_tags
      expect(record.proxied).to eq(true)
      expect(record.comment).to be_nil
      # But original_comment captured before extend still has cf_tags
      expect(original_comment).to eq("cf_tags=cf-proxied:true")
    end
  end

  context "sending proxied status to Cloudflare API" do
    it "includes proxied field in API requests when set" do
      http_client = double("HTTP")
      expect(http_client).to receive(:post).with("", hash_including(proxied: true)).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      record = Zonesync::Record.new(name: "www.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: "cf_tags=cf-proxied:true")
      record.extend(Zonesync::Cloudflare::ProxiedSupport)

      cloudflare.add(record)
    end

    it "does not include proxied field when nil" do
      http_client = double("HTTP")
      expect(http_client).to receive(:post).with("", hash_excluding(:proxied)).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      record = Zonesync::Record.new(name: "mail.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil)
      cloudflare.add(record)
    end
  end

  context "record lookup" do
    it "can change records without ProxiedSupport (e.g. manifest records)" do
      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [
          { "id" => "123", "name" => "zonesync_manifest.example.com", "type" => "TXT", "content" => "old-value", "ttl" => 3600, "proxied" => false, "comment" => nil }
        ]
      })
      expect(http_client).to receive(:patch).with("/123", hash_including(content: '"new-value"')).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      # Simulate a manifest record created without ProxiedSupport
      # The old_record must match what to_record produces from the API response
      old_record = Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"old-value"',
        comment: nil,
      )
      new_record = Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"new-value"',
        comment: nil,
      )

      cloudflare.change(old_record, new_record)
    end
  end

  context "end-to-end proxy status sync" do
    it "syncs proxy status changes from zone file to Cloudflare" do
      zone_file = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        example.com. 1 SOA ns.example.com. admin.example.com. 2000010101 1 1 1 1
        www          IN A     192.0.2.1 ; cf_tags=cf-proxied:true
      ZONEFILE

      http_client = double("HTTP")
      allow(http_client).to receive(:get).with("/..").and_return({ "result" => { "name" => "example.com" } })
      allow(http_client).to receive(:get).with("").and_return({
        "result" => [{ "id" => "123", "name" => "www.example.com", "type" => "A", "content" => "192.0.2.1", "ttl" => 3600, "proxied" => false }]
      })
      expect(http_client).to receive(:patch).with("/123", hash_including(proxied: true)).and_return({ "result" => {}, "success" => true })

      cloudflare = Zonesync::Cloudflare.new({})
      allow(cloudflare).to receive(:http).and_return(http_client)

      zonefile = Zonesync::Zonefile.load(zone_file)
      source_record = zonefile.records.find { |r| r.name == "www.example.com." }
      source_record.extend(Zonesync::Cloudflare::ProxiedSupport)
      expect(source_record.proxied).to eq(true)

      existing_records = cloudflare.all
      existing_record = existing_records.keys.find { |r| r.name == "www.example.com." }
      expect(existing_record.proxied).to eq(false)

      cloudflare.change(existing_record, source_record)
    end
  end
end

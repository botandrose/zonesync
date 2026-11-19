require "zonesync"

describe "Pointing a Cloudflare zone's apex at a CNAME" do
  let(:apex_a) { Zonesync::Record.new(name: "example.com.", type: "A", ttl: 1, rdata: "192.0.2.1", comment: nil) }
  let(:apex_txt) { Zonesync::Record.new(name: "example.com.", type: "TXT", ttl: 1, rdata: %("v=spf1 -all"), comment: nil) }
  let(:www_a) { Zonesync::Record.new(name: "www.example.com.", type: "A", ttl: 1, rdata: "192.0.2.1", comment: nil) }
  let(:api_a) { Zonesync::Record.new(name: "api.example.com.", type: "A", ttl: 1, rdata: "192.0.2.2", comment: nil) }
  let(:manifest) { [apex_a, apex_txt, www_a].map { |r| Zonesync::RecordHash.generate(r) }.join(",") }

  let(:cloudflare) do
    http = double("HTTP")
    allow(http).to receive(:get).with("/..").and_return({ "result" => { "name" => "example.com" } })
    allow(http).to receive(:get).with("").and_return({ "result" => [
      { "id" => "1", "name" => "example.com", "type" => "A", "content" => "192.0.2.1", "ttl" => 1, "proxied" => true, "comment" => nil },
      { "id" => "2", "name" => "example.com", "type" => "TXT", "content" => %("v=spf1 -all"), "ttl" => 1, "proxied" => false, "comment" => nil },
      { "id" => "3", "name" => "www.example.com", "type" => "A", "content" => "192.0.2.1", "ttl" => 1, "proxied" => true, "comment" => nil },
      { "id" => "4", "name" => "api.example.com", "type" => "A", "content" => "192.0.2.2", "ttl" => 1, "proxied" => false, "comment" => nil },
      { "id" => "5", "name" => "zonesync_manifest.example.com", "type" => "TXT", "content" => %("#{manifest}"), "ttl" => 1, "proxied" => false, "comment" => nil },
    ] })
    cloudflare = Zonesync::Cloudflare.new({})
    allow(cloudflare).to receive(:http).and_return(http)
    cloudflare
  end

  let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

  context "when the apex A record becomes a CNAME beside the apex TXT record" do
    let(:source_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 1
      @   CNAME abc123.cfargotunnel.com. ; cf_tags=cf-proxied:true
      @   TXT   "v=spf1 -all"
      www A     192.0.2.1 ; cf_tags=cf-proxied:true
    RECORDS

    it "removes the A record and adds the CNAME, since Cloudflare flattens apex CNAMEs" do
      operations = cloudflare.diff!(source)

      expect(operations.map { |method, (record)| [method, record.name, record.type] }).to eq([
        [:remove, "example.com.", "A"],
        [:add, "example.com.", "CNAME"],
      ])
    end
  end

  context "when a CNAME is added below the apex beside an unmanaged A record" do
    let(:source_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 1
      @   A     192.0.2.1 ; cf_tags=cf-proxied:true
      @   TXT   "v=spf1 -all"
      www A     192.0.2.1 ; cf_tags=cf-proxied:true
      api CNAME abc123.cfargotunnel.com.
    RECORDS

    it "still raises a ConflictError naming the A record" do
      expect {
        cloudflare.diff!(source)
      }.to raise_error(Zonesync::ConflictError, /existing: api\.example\.com\. 1 A 192\.0\.2\.2/)
    end
  end
end

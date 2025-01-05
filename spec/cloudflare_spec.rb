require "zonesync"
require "webmock/rspec"

describe Zonesync::Cloudflare do
  subject do
    described_class.new({ zone_id: 1234, email: "test@example.com", key: "abc123" })
  end

  before do
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/1234/dns_records")
      .with({
        headers: {
          "Content-Type" => "application/json",
          "X-Auth-Email" => "test@example.com",
          "X-Auth-Key" => "abc123",
        }
      })
      .to_return(status: 200, body: <<~JSON, headers: { "Content-Type" => "application/json" })
        {
          "errors": [],
          "messages": [],
          "result": [
            {
              "content": "198.51.100.4",
              "name": "example.com",
              "proxied": false,
              "type": "A",
              "comment": "Domain verification record",
              "created_on": "2014-01-01T05:20:00.12345Z",
              "id": "5678",
              "locked": false,
              "meta": {
                "auto_added": true,
                "source": "primary"
              },
              "modified_on": "2014-01-01T05:20:00.12345Z",
              "proxiable": true,
              "tags": [],
              "ttl": 3600,
              "zone_id": "023e105f4ecef8ad9ca31a8372d0c353",
              "zone_name": "example.com"
            }
          ],
          "success": true,
          "result_info": {
            "count": 1,
            "page": 1,
            "per_page": 20,
            "total_count": 1
          }
        }
      JSON
  end

  describe "read" do
    it "works" do
      stub_request(:get, "https://api.cloudflare.com/client/v4/zones/1234/")
        .with({
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: '{"result":{"name":"example.com"}}', headers: { "Content-Type" => "application/json" })

      expect(subject.read).to eq(<<~ZONEFILE)
        example.com. 1 SOA example.com admin.example.com 2000010101 1 1 1 1
        example.com. 3600 A 198.51.100.4 ; Domain verification record
      ZONEFILE
    end
  end

  describe "remove" do
    it "works" do
      stub_request(:delete, "https://api.cloudflare.com/client/v4/zones/1234/dns_records/5678")
        .with({
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: <<~JSON, headers: { "Content-Type" => "application/json" })
          {
            "result": {
              "id": "5678"
            }
          }
        JSON

      subject.remove({
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: "Domain verification record",
      })
    end
  end

  describe "change" do
    it "works" do
      stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/1234/dns_records/5678")
        .with({
          body: JSON.dump({
            "name": "www.example.com.",
            "type": "A",
            "ttl": 7200,
            "content": "198.51.100.4",
            "comment": "Domain verification record",
          }),
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: <<~JSON, headers: { "Content-Type" => "application/json" })
          {
            "result": {},
            "success": true
          }
        JSON

      subject.change({
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: "Domain verification record",
      },{
        name: "www.example.com.",
        type: "A",
        ttl: 7200,
        rdata: "198.51.100.4",
        comment: "Domain verification record",
      })
    end
  end

  describe "add" do
    it "works" do
      stub_request(:post, "https://api.cloudflare.com/client/v4/zones/1234/dns_records")
        .with({
          body: JSON.dump({
            "name": "example.com.",
            "type": "A",
            "ttl": 3600,
            "content": "198.51.100.4",
            "comment": "Domain verification record",
          }),
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: <<~JSON, headers: { "Content-Type" => "application/json" })
          {
            "result": {},
            "success": true
          }
        JSON

      subject.add({
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: "Domain verification record",
      })
    end
  end
end

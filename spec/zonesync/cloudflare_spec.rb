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
      .to_return(status: 200, body: <<~JSON, headers: {})
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
      stub_request(:get, "https://api.cloudflare.com/client/v4/zones/1234/dns_records/export")
        .with({
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: "dummy", headers: {})

      expect(subject.read).to eq("dummy")
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
        .to_return(status: 200, body: <<~JSON, headers: {})
          {
            "result": {
              "id": "5678"
            }
          }
        JSON

      subject.remove({
        type: "A",
        host: "example.com",
        ttl: 3600,
        address: "198.51.100.4",
      })
    end
  end

  describe "change" do
    it "works" do
      stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/1234/dns_records/5678")
        .with({
          body: JSON.dump({
              "content": "198.51.100.4",
              "name": "www.example.com",
              "type": "A",
              "ttl": 7200
          }),
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: <<~JSON, headers: {})
          {
            "result": {},
            "success": true
          }
        JSON

      subject.change({
        type: "A",
        host: "example.com",
        ttl: 3600,
        address: "198.51.100.4",
      },{
        type: "A",
        host: "www.example.com",
        ttl: 7200,
        address: "198.51.100.4",
      })
    end
  end

  describe "add" do
    it "works" do
      stub_request(:post, "https://api.cloudflare.com/client/v4/zones/1234/dns_records")
        .with({
          body: JSON.dump({
            "content": "198.51.100.4",
            "name": "example.com",
            "type": "A",
            "ttl": 3600,
          }),
          headers: {
           "Content-Type" => "application/json",
           "X-Auth-Email" => "test@example.com",
           "X-Auth-Key"   => "abc123",
          }
        })
        .to_return(status: 200, body: <<~JSON, headers: {})
          {
            "result": {},
            "success": true
          }
        JSON

      subject.add({
        type: "A",
        host: "example.com",
        ttl: 3600,
        address: "198.51.100.4",
      })
    end
  end
end

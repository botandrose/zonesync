require "zonesync"

describe "Manifest.generate switching to v2" do
  let(:zone) { double("zone", origin: "example.com.") }
  let(:records) do
    [
      Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
      Zonesync::Record.new(name: "example.com.", type: "TXT", ttl: 3600, rdata: '"v=spf1 include:spf.protection.outlook.com -all"', comment: nil)
    ]
  end
  let(:manifest) { Zonesync::Manifest.new(records, zone) }

  it "generates hash-based manifest format" do
    result = manifest.generate

    expect(result.name).to eq("zonesync_manifest.example.com.")
    expect(result.type).to eq("TXT")
    expect(result.ttl).to eq(3600)
    expect(result.rdata).to eq('"1r81el0,td1ulz"')
    expect(result.comment).to be_nil
  end
end
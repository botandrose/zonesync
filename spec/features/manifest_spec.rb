require "zonesync"

describe Zonesync::Sync do
  let(:destination_records) { <<~RECORDS }
    $ORIGIN example.com.
    $TTL 3600
    @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
    @                 NS    ns.somewhere.example.
    @                 A     192.0.2.1
    ssh               A     192.0.2.1
    mail              A     192.0.2.3
    www               CNAME example.com.
    @                 MX    10 mail.example.com.
    @                 MX    20 mail2.example.com.
    zonesync_manifest TXT   "{A:['@','mail','ssh'], CNAME:['www'], MX:['@','@']}"
  RECORDS

  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

  it "ignores manifest record if it matches" do
    described_class.new(
      Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
        ssh  A     192.0.2.1
        mail A     192.0.2.3
        www  CNAME example.com.
        @    MX    10 mail.example.com.
        @    MX    20 mail2.example.com.
      RECORDS
      destination,
    ).call
  end

  it "writes a new manifest record if it doesn't match" do
    expect(destination).to receive(:add).with({
      name: "example.com.",
      type: "MX",
      ttl: 3600,
      rdata: "30 mail3.example.com.",
      comment: nil,
    })

    expect(destination).to receive(:change).with({
      name: "zonesync_manifest.example.com.",
      type: "TXT",
      ttl: 3600,
      rdata: %("{A:['@','mail','ssh'], CNAME:['www'], MX:['@','@']}"),
      comment: nil,
    },{
      name: "zonesync_manifest.example.com.",
      type: "TXT",
      ttl: 3600,
      rdata: %("{A:['@','mail','ssh'], CNAME:['www'], MX:['@','@','@']}"),
      comment: nil,
    })

    described_class.new(
      Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
        ssh  A     192.0.2.1
        mail A     192.0.2.3
        www  CNAME example.com.
        @    MX    10 mail.example.com.
        @    MX    20 mail2.example.com.
        @    MX    30 mail3.example.com.
      RECORDS
      destination,
    ).call
  end
end



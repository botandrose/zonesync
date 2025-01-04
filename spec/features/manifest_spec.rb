require "zonesync"

describe Zonesync::Sync do
  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

  context "with an existing manifest record" do
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
      zonesync_manifest TXT   "A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"
    RECORDS

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
        rdata: '"A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20"',
        comment: nil,
      },{
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"A:@,mail,ssh;CNAME:www;MX:@ 10,@ 20,@ 30"',
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

  context "with a manifest record and some additional records" do
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
      zonesync_manifest TXT   "A:@,mail;CNAME:www;MX:@ 10"
    RECORDS

    it "ignores records that are not on the manifest" do
      expect(destination).to receive(:add).with({
        name: "test.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.4",
        comment: nil,
      })
      expect(destination).to receive(:change).with({
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"A:@,mail;CNAME:www;MX:@ 10"',
        comment: nil,
      },{
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"A:@,mail,test;CNAME:www;MX:@ 10"',
        comment: nil,
      })

      described_class.new(
        Zonesync::Provider.from({ provider: "Memory", string: <<~RECORDS }),
          $ORIGIN example.com.
          $TTL 3600
          @    A     192.0.2.1
          mail A     192.0.2.3
          test A     192.0.2.4
          www  CNAME example.com.
          @    MX    10 mail.example.com.
        RECORDS
        destination,
      ).call
    end
    it "errors when there's a conflict between ignored records and new ones"
  end

  context "with an missing manifest record" do
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
    RECORDS

    it "errors"
  end
end



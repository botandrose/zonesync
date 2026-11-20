require "zonesync"
require "webmock/rspec"
require "stringio"

describe "Route53 alias records" do
  let(:url) { "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset" }

  let(:route53) do
    Zonesync::Provider.from({
      provider: "Route53",
      hosted_zone_id: "Z3P5QSUBK4POTI",
      aws_access_key_id: "mock_access_key",
      aws_secret_access_key: "mock_secret_key",
    })
  end

  let(:zonefile) { Zonesync::Provider.from({ provider: "Memory", string: <<~ZONEFILE }) }
    $ORIGIN rehabengage.org.
    $TTL 300
    @   A    d111abcdef8.cloudfront.net. ; route53-alias
    @   AAAA d111abcdef8.cloudfront.net. ; route53-alias
    www A    d111abcdef8.cloudfront.net. ; route53-alias
    www AAAA d111abcdef8.cloudfront.net. ; route53-alias
  ZONEFILE

  def a_record(name)
    Zonesync::Record.new(name: name, type: "A", ttl: 300, rdata: "18.210.167.234", comment: nil)
  end

  def alias_record(name, type)
    Zonesync::Record.new(name: name, type: type, ttl: nil, rdata: "d111abcdef8.cloudfront.net.", comment: "route53-alias")
  end

  def manifest_for(*records)
    records.sort.map { |r| Zonesync::RecordHash.generate(r) }.join(",")
  end

  def a_rrset(name)
    <<~XML
      <ResourceRecordSet>
        <Name>#{name}</Name>
        <Type>A</Type>
        <TTL>300</TTL>
        <ResourceRecords><ResourceRecord><Value>18.210.167.234</Value></ResourceRecord></ResourceRecords>
      </ResourceRecordSet>
    XML
  end

  def alias_rrset(name, type)
    <<~XML
      <ResourceRecordSet>
        <Name>#{name}</Name>
        <Type>#{type}</Type>
        <AliasTarget>
          <HostedZoneId>Z2FDTNDATAQYW2</HostedZoneId>
          <DNSName>d111abcdef8.cloudfront.net.</DNSName>
          <EvaluateTargetHealth>false</EvaluateTargetHealth>
        </AliasTarget>
      </ResourceRecordSet>
    XML
  end

  def stub_rrsets(*rrsets, manifest:)
    stub_request(:get, url).to_return(status: 200, headers: { "Content-Type" => "application/xml" }, body: <<~XML)
      <?xml version="1.0"?>
      <ListResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
        <ResourceRecordSets>
          <ResourceRecordSet>
            <Name>rehabengage.org.</Name>
            <Type>SOA</Type>
            <TTL>900</TTL>
            <ResourceRecords><ResourceRecord><Value>ns-1.awsdns-01.org. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400</Value></ResourceRecord></ResourceRecords>
          </ResourceRecordSet>
          #{rrsets.join}
          <ResourceRecordSet>
            <Name>zonesync_manifest.rehabengage.org.</Name>
            <Type>TXT</Type>
            <TTL>3600</TTL>
            <ResourceRecords><ResourceRecord><Value>"#{manifest}"</Value></ResourceRecord></ResourceRecords>
          </ResourceRecordSet>
        </ResourceRecordSets>
      </ListResourceRecordSetsResponse>
    XML
  end

  def stub_alias_change(action, name, type)
    stub_request(:post, url).with(body: <<~XML).to_return(status: 200, headers: { "Content-Type" => "application/xml" }, body: "<ChangeResourceRecordSetsResponse/>")
      <?xml version="1.0" encoding="UTF-8"?>
      <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
        <ChangeBatch>
          <Changes>
            <Change>
              <Action>#{action}</Action>
              <ResourceRecordSet>
                <Name>#{name}</Name>
                <Type>#{type}</Type>
                <AliasTarget>
                  <HostedZoneId>Z2FDTNDATAQYW2</HostedZoneId>
                  <DNSName>d111abcdef8.cloudfront.net.</DNSName>
                  <EvaluateTargetHealth>false</EvaluateTargetHealth>
                </AliasTarget>
              </ResourceRecordSet>
            </Change>
          </Changes>
        </ChangeBatch>
      </ChangeResourceRecordSetsRequest>
    XML
  end

  let(:aliases) do
    %w[rehabengage.org. www.rehabengage.org.].product(%w[A AAAA]).map { |name, type| alias_record(name, type) }
  end

  context "when managed A records become CloudFront aliases" do
    before do
      stub_rrsets(
        a_rrset("rehabengage.org."),
        a_rrset("www.rehabengage.org."),
        manifest: manifest_for(a_record("rehabengage.org."), a_record("www.rehabengage.org.")),
      )
    end

    it "upserts each A record into an alias in place, creates the AAAA aliases, and tracks them all in the manifest" do
      upserts = %w[rehabengage.org. www.rehabengage.org.].map { |name| stub_alias_change("UPSERT", name, "A") }
      creates = %w[rehabengage.org. www.rehabengage.org.].map { |name| stub_alias_change("CREATE", name, "AAAA") }
      manifest = stub_request(:post, url)
        .with(body: /<Action>UPSERT<\/Action>.*<Value>"#{manifest_for(*aliases)}"<\/Value>/m)
        .to_return(status: 200, headers: { "Content-Type" => "application/xml" }, body: "<ChangeResourceRecordSetsResponse/>")

      Zonesync::Sync.new(zonefile, route53).call

      (upserts + creates + [manifest]).each { |request| expect(request).to have_been_requested.once }
    end

    it "prints each change on a dry run" do
      expect {
        Zonesync::Sync.new(zonefile, route53).call(dry_run: true)
      }.to output(a_string_including(
        "Change \nrehabengage.org. A 300 18.210.167.234 ->\nrehabengage.org. A d111abcdef8.cloudfront.net. route53-alias\n",
        "Change \nwww.rehabengage.org. A 300 18.210.167.234 ->\nwww.rehabengage.org. A d111abcdef8.cloudfront.net. route53-alias\n",
        "Add rehabengage.org. AAAA d111abcdef8.cloudfront.net. route53-alias\n",
        "Add www.rehabengage.org. AAAA d111abcdef8.cloudfront.net. route53-alias\n",
      )).to_stdout_from_any_process
    end
  end

  context "when Route53 already serves the aliases" do
    before do
      stub_rrsets(*aliases.map { |r| alias_rrset(r.name, r.type) }, manifest: manifest_for(*aliases))
    end

    it "has nothing to sync" do
      expect(route53.diff!(route53.interpret(zonefile))).to eq([])
    end

    it "keeps the manifest hashes of the first release: an alias hashes as name:type::target" do
      expected = Zlib.crc32("rehabengage.org.:A::d111abcdef8.cloudfront.net.").to_s(36)
      expect(route53.interpret(zonefile).manifest.generate.rdata).to include(expected)
    end

    it "ignores the TTL and any other comment on an alias's Zonefile line" do
      zonefile.config[:string] = zonefile.read.sub("@   A    d111abcdef8.cloudfront.net. ; route53-alias", "@ 600 A d111abcdef8.cloudfront.net. ; route53-alias the apex")
      expect(route53.diff!(route53.interpret(zonefile))).to eq([])
    end

    it "generates a Zonefile that reads back as the same records" do
      generated = Zonesync::Provider.from({ provider: "Memory", string: "" })
      Zonesync::Generate.new(route53, generated).call

      expect(generated.read.lines).to include(
        "rehabengage.org. A d111abcdef8.cloudfront.net. ; route53-alias\n",
        "rehabengage.org. AAAA d111abcdef8.cloudfront.net. ; route53-alias\n",
        "www.rehabengage.org. A d111abcdef8.cloudfront.net. ; route53-alias\n",
        "www.rehabengage.org. AAAA d111abcdef8.cloudfront.net. ; route53-alias\n",
      )
      expect(route53.diff!(route53.interpret(generated))).to eq([])
    end

    it "has nothing to repair" do
      output = StringIO.new
      Zonesync::Repair.new(zonefile, route53).call(input: StringIO.new, output: output)
      expect(output.string).to include("Already in sync!")
    end
  end

  context "when an alias is added where Route53 holds an untracked A record" do
    before do
      stub_rrsets(a_rrset("rehabengage.org."), a_rrset("www.rehabengage.org."), manifest: manifest_for(a_record("rehabengage.org.")))
    end

    it "refuses, since the alias would replace the whole RRset" do
      zonefile.config[:string] = <<~ZONEFILE
        $ORIGIN rehabengage.org.
        $TTL 300
        @   A 18.210.167.234
        www A d111abcdef8.cloudfront.net. ; route53-alias
      ZONEFILE

      expect {
        Zonesync::Sync.new(zonefile, route53).call(dry_run: true)
      }.to raise_error(Zonesync::ConflictError, /existing: www\.rehabengage\.org\. 300 A 18\.210\.167\.234/)
    end
  end

  context "when the destination is Cloudflare" do
    let(:cloudflare) { Zonesync::Provider.from({ provider: "Cloudflare", zone_id: "abc123", token: "secret" }) }

    it "refuses an A record that names a host before touching Cloudflare" do
      expect {
        Zonesync::Sync.new(zonefile, cloudflare).call
      }.to raise_error(Zonesync::UnsupportedRecordError, /Cloudflare can't hold an A or AAAA record that names a host.*rehabengage\.org\. 300 A d111abcdef8\.cloudfront\.net\. ; route53-alias/m)
    end
  end
end

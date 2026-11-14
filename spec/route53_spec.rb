require "zonesync"
require "webmock/rspec"

describe Zonesync::Route53 do
  subject do
    described_class.new({
      hosted_zone_id: "Z3P5QSUBK4POTI",
      aws_region: "us-east-1",
      aws_access_key_id: "mock_access_key",
      aws_secret_access_key: "mock_secret_key",
    })
  end

  describe "read" do
    it "works" do
      stub_request(:get, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0"?>
          <ListResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ResourceRecordSets>
                  <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>A</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                          <ResourceRecord>
                              <Value>198.51.100.4</Value>
                          </ResourceRecord>
                      </ResourceRecords>
                  </ResourceRecordSet>
              </ResourceRecordSets>
          </ListResourceRecordSetsResponse>
        XML

      # stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
      #   .to_return(status: 200, body: JSON.dump({
      #     "ChangeInfo": { "Id": "mock_change_id" }
      #   }), headers: { "Content-Type" => "application/json" })

      expect(subject.read).to eq("example.com. 3600 A 198.51.100.4\n")
    end
  end

  describe "remove" do
    it "works" do
      allow(subject).to receive(:records).and_return([
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "198.51.100.4", comment: nil)
      ])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>DELETE</Action>
                  <ResourceRecordSet>
                    <Name>example.com.</Name>
                    <Type>A</Type>
                    <TTL>3600</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>198.51.100.4</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo>
              <Id>/change/C2682N5HXP0BZ4</Id>
              <Status>PENDING</Status>
              <SubmittedAt>2025-01-04T00:30:09.123Z</SubmittedAt>
              <Comment>Delete a record set</Comment>
            </ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      subject.remove(Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: nil,
      ))
    end
  end

  describe "change" do
    it "self-heals a zonesync_manifest RRset that has accumulated stale duplicate entries" do
      # Past bugs or races could leave the manifest TXT RRset with more than
      # one record. The captured old_record only matches one of them, so the
      # generic reject-by-equality path would preserve the other(s) and the
      # RRset would never converge to a singleton. change() must full-replace.
      old_record = Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"oldhash1,oldhash2"',
        comment: nil
      )
      stale_duplicate = Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"someotherhash"',
        comment: nil
      )
      new_record = Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"newhash1,newhash2,newhash3"',
        comment: nil
      )
      allow(subject).to receive(:records).and_return([old_record, stale_duplicate])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>UPSERT</Action>
                  <ResourceRecordSet>
                    <Name>zonesync_manifest.example.com.</Name>
                    <Type>TXT</Type>
                    <TTL>3600</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>"newhash1,newhash2,newhash3"</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo><Id>/change/C1</Id><Status>PENDING</Status></ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      subject.change(old_record, new_record)
    end

    it "comments shouldn't be considered in the match" do
      captured_old = Zonesync::Record.new(
        name: "spf.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"v=spf1 -all"',
        comment: "old comment"
      )
      fresh_existing = Zonesync::Record.new(
        name: "spf.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"v=spf1 -all"',
        comment: nil
      )
      new_record = Zonesync::Record.new(
        name: "spf.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: '"v=spf1 include:mail.example.com -all"',
        comment: nil
      )
      allow(subject).to receive(:records).and_return([fresh_existing])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>UPSERT</Action>
                  <ResourceRecordSet>
                    <Name>spf.example.com.</Name>
                    <Type>TXT</Type>
                    <TTL>3600</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>"v=spf1 include:mail.example.com -all"</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo><Id>/change/C2</Id><Status>PENDING</Status></ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      subject.change(captured_old, new_record)
    end

    it "uses a single UPSERT for TTL-only changes" do
      allow(subject).to receive(:records).and_return([
        Zonesync::Record.new(name: "spektrix.pica.org.", type: "CNAME", ttl: 3600, rdata: "customers.spektrix.com.", comment: nil)
      ])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>UPSERT</Action>
                  <ResourceRecordSet>
                    <Name>spektrix.pica.org.</Name>
                    <Type>CNAME</Type>
                    <TTL>600</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>customers.spektrix.com.</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo>
              <Id>/change/C2682N5HXP0BZ4</Id>
              <Status>PENDING</Status>
              <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
              <Comment>Upsert a record set</Comment>
            </ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      subject.change(Zonesync::Record.new(
        name: "spektrix.pica.org.",
        type: "CNAME",
        ttl: 3600,
        rdata: "customers.spektrix.com.",
        comment: nil
      ), Zonesync::Record.new(
        name: "spektrix.pica.org.",
        type: "CNAME",
        ttl: 600,
        rdata: "customers.spektrix.com.",
        comment: nil
      ))
    end
  end

  describe "add" do
    it "works" do
      allow(subject).to receive(:records).and_return([])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>CREATE</Action>
                  <ResourceRecordSet>
                    <Name>example.com.</Name>
                    <Type>A</Type>
                    <TTL>3600</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>198.51.100.4</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo>
              <Id>/change/C2682N5HXP0BZ4</Id>
              <Status>PENDING</Status>
              <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
              <Comment>Create an A record</Comment>
            </ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      subject.add(Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: nil
      ))
    end

    it "sends CAA records with flags, tag and quoted value" do
      allow(subject).to receive(:records).and_return([])

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: /<Type>CAA<\/Type>\s*<TTL>3600<\/TTL>\s*<ResourceRecords>\s*<ResourceRecord>\s*<Value>0 issue "amazon.com"<\/Value>/)
        .to_return(status: 200, body: "<ChangeResourceRecordSetsResponse/>", headers: { "Content-Type" => "application/xml" })

      subject.add(Zonesync::Record.new(
        name: "example.com.",
        type: "CAA",
        ttl: 3600,
        rdata: '0 issue "amazon.com"',
        comment: nil
      ))
    end

    context "with single TXT records" do
      it "adds a single TXT record normally" do
        # Mock no existing TXT records with the same name
        allow(subject).to receive(:records).and_return([])

        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>CREATE</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com -all"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Create TXT record</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        subject.add(Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
          comment: nil
        ))
      end

      it "removes a single TXT record normally" do
        # Mock existing single TXT record
        allow(subject).to receive(:records).and_return([
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
            comment: nil
          )
        ])

        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>DELETE</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com -all"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Delete TXT record</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        subject.remove(Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
          comment: nil
        ))
      end

      it "changes a single TXT record with UPSERT" do
        old_record = Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
          comment: nil
        )

        new_record = Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com include:networkforgood.com -all"',
          comment: nil
        )

        allow(subject).to receive(:records).and_return([old_record])

        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>UPSERT</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com include:networkforgood.com -all"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Change TXT record</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        subject.change(old_record, new_record)
      end
    end

    context "with multiple TXT records for the same name" do
      it "combines them into a single ResourceRecordSet when adding" do
        # Mock existing records to include some TXT records
        allow(subject).to receive(:records).and_return([
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"',
            comment: nil
          ),
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
            comment: nil
          )
        ])

        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>UPSERT</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com -all"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Create TXT records</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        subject.add(Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"',
          comment: nil
        ))
      end

      it "recreates remaining TXT records when removing one" do
        # Mock existing records to include multiple TXT records
        allow(subject).to receive(:records).and_return([
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"',
            comment: nil
          ),
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
            comment: nil
          ),
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"',
            comment: nil
          )
        ])

        # First DELETE all TXT records, then CREATE the remaining ones
        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>DELETE</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com -all"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                  <Change>
                    <Action>CREATE</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Update TXT records</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        # Remove the SPF record
        subject.remove(Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
          comment: nil
        ))
      end

      it "handles changing one TXT record among multiple with UPSERT" do
        old_record = Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com -all"',
          comment: nil
        )

        new_record = Zonesync::Record.new(
          name: "example.com.",
          type: "TXT",
          ttl: 3600,
          rdata: '"v=spf1 include:spf.protection.outlook.com include:networkforgood.com -all"',
          comment: nil
        )

        allow(subject).to receive(:records).and_return([
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"',
            comment: nil
          ),
          old_record,
          Zonesync::Record.new(
            name: "example.com.",
            type: "TXT",
            ttl: 3600,
            rdata: '"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"',
            comment: nil
          )
        ])

        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeBatch>
                <Changes>
                  <Change>
                    <Action>UPSERT</Action>
                    <ResourceRecordSet>
                      <Name>example.com.</Name>
                      <Type>TXT</Type>
                      <TTL>3600</TTL>
                      <ResourceRecords>
                        <ResourceRecord>
                          <Value>"MS=98F6AEAAA2E720DA0383C6253097E187749ED7B5"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"</Value>
                        </ResourceRecord>
                        <ResourceRecord>
                          <Value>"v=spf1 include:spf.protection.outlook.com include:networkforgood.com -all"</Value>
                        </ResourceRecord>
                      </ResourceRecords>
                    </ResourceRecordSet>
                  </Change>
                </Changes>
              </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
          XML
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo>
                <Id>/change/C2682N5HXP0BZ4</Id>
                <Status>PENDING</Status>
                <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
                <Comment>Change TXT record</Comment>
              </ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        subject.change(old_record, new_record)
      end

      it "should use UPSERT when adding TXT records to existing record set" do
        # Mock existing TXT record already in Route53
        allow(subject).to receive(:records).and_return([
          Zonesync::Record.new(
            name: "filmpreservation.org.",
            type: "TXT",
            ttl: 3600,
            rdata: '"v=spf1 include:spf.protection.outlook.com include:networkforgood.com include:networkforgood.org -all"',
            comment: nil
          )
        ])

        # Expect UPSERT action instead of CREATE when records already exist
        stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
          .with(body: /<Action>UPSERT<\/Action>.*filmpreservation\.org.*TXT/m)
          .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
            <?xml version="1.0" encoding="UTF-8"?>
            <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ChangeInfo><Id>/change/C2</Id><Status>PENDING</Status></ChangeInfo>
            </ChangeResourceRecordSetsResponse>
          XML

        # This should succeed by using UPSERT instead of CREATE
        expect {
          subject.add(Zonesync::Record.new(
            name: "filmpreservation.org.",
            type: "TXT",
            ttl: 3600,
            rdata: '"google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"',
            comment: nil
          ))
        }.not_to raise_error
      end
    end
  end

  describe "apply" do
    it "changes a record's type at one name with a single batch that deletes before creating" do
      cname = Zonesync::Record.new(name: "ctm-api.example.com.", type: "CNAME", ttl: 300, rdata: "d1uj4th7l3tvms.cloudfront.net.", comment: nil)
      a = Zonesync::Record.new(name: "ctm-api.example.com.", type: "A", ttl: 1800, rdata: "3.83.71.52", comment: nil)
      allow(subject).to receive(:records).and_return([cname])

      request = stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>DELETE</Action>
                  <ResourceRecordSet>
                    <Name>ctm-api.example.com.</Name>
                    <Type>CNAME</Type>
                    <TTL>300</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>d1uj4th7l3tvms.cloudfront.net.</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
                <Change>
                  <Action>CREATE</Action>
                  <ResourceRecordSet>
                    <Name>ctm-api.example.com.</Name>
                    <Type>A</Type>
                    <TTL>1800</TTL>
                    <ResourceRecords>
                      <ResourceRecord>
                        <Value>3.83.71.52</Value>
                      </ResourceRecord>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML
        .to_return(status: 200, body: <<~XML, headers: { "Content-Type" => "application/xml" })
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeInfo>
              <Id>/change/C2682N5HXP0BZ4</Id>
              <Status>PENDING</Status>
              <SubmittedAt>2025-01-04T00:37:31.123Z</SubmittedAt>
            </ChangeInfo>
          </ChangeResourceRecordSetsResponse>
        XML

      logged = []
      subject.apply([[:remove, [cname]], [:add, [a]]]) { |method, records| logged << [method, records] }

      expect(request).to have_been_made.once
      expect(logged).to eq([[:remove, [cname]], [:add, [a]]])
    end
  end
end


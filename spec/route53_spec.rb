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
    it "works" do
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

      stub_request(:post, "https://route53.amazonaws.com/2013-04-01/hostedzone/Z3P5QSUBK4POTI/rrset")
        .with(body: <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <Change>
                  <Action>CREATE</Action>
                  <ResourceRecordSet>
                    <Name>www.example.com.</Name>
                    <Type>A</Type>
                    <TTL>7200</TTL>
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

      subject.change(Zonesync::Record.new(
        name: "example.com.",
        type: "A",
        ttl: 3600,
        rdata: "198.51.100.4",
        comment: nil
      ), Zonesync::Record.new(
        name: "www.example.com.",
        type: "A",
        ttl: 7200,
        rdata: "198.51.100.4",
        comment: nil
      ))
    end
  end

  describe "add" do
    it "works" do
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

      it "changes a single TXT record normally" do
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

        # Should call remove and add with normal single record behavior
        expect(subject).to receive(:remove).with(old_record)
        expect(subject).to receive(:add).with(new_record)

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

      it "handles changing one TXT record among multiple" do
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

        # Mock existing records
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

        # Should call remove (which handles TXT grouping) and then add (which handles TXT grouping)
        expect(subject).to receive(:remove).with(old_record)
        expect(subject).to receive(:add).with(new_record)

        subject.change(old_record, new_record)
      end
    end
  end
end


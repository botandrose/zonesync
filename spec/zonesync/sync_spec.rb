require "zonesync"

describe Zonesync::Sync do
  let(:records) { <<~RECORDS }
    $ORIGIN example.com.     ; designates the start of this zone file in the namespace
    $TTL 3h                  ; default expiration time of all resource records without their own TTL value
    example.com.  IN  SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
    example.com.  IN  NS    ns                    ; ns.example.com is a nameserver for example.com
    example.com.  IN  NS    ns.somewhere.example. ; ns.somewhere.example is a backup nameserver for example.com
    example.com.  IN  MX    10 mail.example.com.  ; mail.example.com is the mailserver for example.com
    @             IN  MX    20 mail2.example.com. ; equivalent to above line, "@" represents zone origin
    example.com.  IN  A     192.0.2.1             ; IPv4 address for example.com
                  IN  AAAA  2001:db8:10::1        ; IPv6 address for example.com
    ns            IN  A     192.0.2.2             ; IPv4 address for ns.example.com
                  IN  AAAA  2001:db8:10::2        ; IPv6 address for ns.example.com
    ssh           IN  A     192.0.2.1             ; IPv4 address for ns.example.com
    www           IN  CNAME example.com.          ; www.example.com is an alias for example.com
    wwwtest       IN  CNAME www                   ; wwwtest.example.com is another alias for www.example.com
    mail          IN  A     192.0.2.3             ; IPv4 address for mail.example.com
    mail2         IN  A     192.0.2.4             ; IPv4 address for mail2.example.com
    mail3         IN  A     192.0.2.6             ; IPv4 address for mail3.example.com comment
  RECORDS

  subject do
    described_class.new(
      { provider: "Filesystem", path: "spec/fixtures/example.com" },
      { provider: "Memory", string: records },
    )
  end

  it "works" do
    expect_any_instance_of(Zonesync::Memory).to receive(:add).with({
      name: "example.com.",
      type: "MX",
      ttl: 3,
      rdata: "50 mail3.example.com.",
      comment: "equivalent to above line, but using a relative host name",
    })
    expect_any_instance_of(Zonesync::Memory).to receive(:remove).with({
      name: "ssh.example.com.",
      type: "A",
      ttl: 3,
      rdata: "192.0.2.1",
      comment: "IPv4 address for ns.example.com",
    })
    expect_any_instance_of(Zonesync::Memory).to receive(:change).with({
      name: "mail3.example.com.",
      type: "A",
      ttl: 3,
      rdata: "192.0.2.6",
      comment: "IPv4 address for mail3.example.com comment",
    },{
      name: "mail3.example.com.",
      type: "A",
      ttl: 3,
      rdata: "192.0.2.5",
      comment: "IPv4 address for mail3.example.com",
    })
    subject.call manifest: false
  end
end


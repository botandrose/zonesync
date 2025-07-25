require "zonesync"

describe Zonesync::Sync do
  let(:records) { <<~RECORDS }
    $ORIGIN example.com.       ; designates the start of this zone file in the namespace
    $TTL 3600                  ; default expiration time of all resource records without their own TTL value
    example.com.      IN SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
    example.com.      IN NS    ns                    ; ns.example.com is a nameserver for example.com
    example.com.      IN NS    ns.somewhere.example. ; ns.somewhere.example is a backup nameserver for example.com
    example.com.      IN MX    10 mail.example.com.  ; mail.example.com is the mailserver for example.com
    @                 IN MX    20 mail2.example.com. ; equivalent to above line, "@" represents zone origin
    example.com.      IN A     192.0.2.1             ; IPv4 address for example.com
                      IN AAAA  2001:db8:10::1        ; IPv6 address for example.com
    ns                IN A     192.0.2.2             ; IPv4 address for ns.example.com
                      IN AAAA  2001:db8:10::2        ; IPv6 address for ns.example.com
    ssh               IN A     192.0.2.1             ; IPv4 address for ns.example.com
    www               IN CNAME example.com.          ; www.example.com is an alias for example.com
    wwwtest           IN CNAME www                   ; wwwtest.example.com is another alias for www.example.com
    mail              IN A     192.0.2.3             ; IPv4 address for mail.example.com
    mail2             IN A     192.0.2.4             ; IPv4 address for mail2.example.com
    mail3             IN A     192.0.2.6             ; IPv4 address for mail3.example.com comment
    zonesync_manifest IN TXT   "A:@,mail,mail2,mail3,ns,ssh;AAAA:@,ns;CNAME:www,wwwtest;MX:@ 10,@ 20"
    zonesync_checksum IN TXT   "3e0c7bf5b2582d41e35d0916bad9fefaa8454c4db632c57f5df0b5edee57f4eb"
  RECORDS

  subject do
    described_class.new(
      Zonesync::Provider.from({ provider: "Filesystem", path: "spec/fixtures/example.com" }),
      Zonesync::Provider.from({ provider: "Memory", string: records }),
    )
  end

  it "works" do
    expect_any_instance_of(Zonesync::Memory).to receive(:add).with(
      Zonesync::Record.new(
        name: "example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "50 mail3.example.com.",
        comment: "equivalent to above line, but using a relative host name",
      )
    )
    expect_any_instance_of(Zonesync::Memory).to receive(:remove).with(
      Zonesync::Record.new(
        name: "ssh.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: "IPv4 address for ns.example.com",
      )
    )
    expect_any_instance_of(Zonesync::Memory).to receive(:change).with(
      Zonesync::Record.new(
        name: "mail3.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.6",
        comment: "IPv4 address for mail3.example.com comment",
      ),
      Zonesync::Record.new(
        name: "mail3.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.5",
        comment: "IPv4 address for mail3.example.com",
      )
    )
    expect_any_instance_of(Zonesync::Memory).to receive(:change).with(
      Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("A:@,mail,mail2,mail3,ns,ssh;AAAA:@,ns;CNAME:www,wwwtest;MX:@ 10,@ 20"),
        comment: nil,
      ),
      Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("A:@,mail,mail2,mail3,ns;AAAA:@,ns;CNAME:www,wwwtest;MX:@ 10,@ 20,@ 50"),
        comment: nil,
      )
    )
    expect_any_instance_of(Zonesync::Memory).to receive(:change).with(
      Zonesync::Record.new(
        name: "zonesync_checksum.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("3e0c7bf5b2582d41e35d0916bad9fefaa8454c4db632c57f5df0b5edee57f4eb"),
        comment: nil,
      ),
      Zonesync::Record.new(
        name: "zonesync_checksum.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("5e531bfddbc5204d117898c784e2194e2491139f7650015b3236542c6f2223e0"),
        comment: nil,
      )
    )
    subject.call
  end
end


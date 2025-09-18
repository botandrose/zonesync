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
    zonesync_manifest IN TXT   "1r81el0,1olaaae,9pp0kg,1d71j6w,60oib3,1ahd1l,1rci27o,b55ux9,9vtk0b,8a2s09,ky0g92,tk3z21"
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
        rdata: %("1r81el0,1olaaae,9pp0kg,1d71j6w,60oib3,1ahd1l,1rci27o,b55ux9,9vtk0b,8a2s09,ky0g92,tk3z21"),
        comment: nil,
      ),
      Zonesync::Record.new(
        name: "zonesync_manifest.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("1r81el0,60oib3,1ahd1l,yrds0e,b55ux9,1olaaae,9vtk0b,ky0g92,tk3z21,9pp0kg,1d71j6w,jbohfq"),
        comment: nil,
      )
    )
    expect_any_instance_of(Zonesync::Memory).to receive(:remove).with(
      Zonesync::Record.new(
        name: "zonesync_checksum.example.com.",
        type: "TXT",
        ttl: 3600,
        rdata: %("3e0c7bf5b2582d41e35d0916bad9fefaa8454c4db632c57f5df0b5edee57f4eb"),
        comment: nil,
      )
    )
    subject.call
  end
end


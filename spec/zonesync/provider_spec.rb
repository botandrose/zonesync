require 'zonesync'
require 'yaml'

describe Zonesync::Provider do
  describe '.call' do
    let(:sample_zone_file_path) { './spec/fixtures/example.com' }
    let(:credentials) { { provider: "Filesystem", path: sample_zone_file_path } }
    subject { described_class.from(credentials) }

    it "#diffable_records" do
      expect(subject.diffable_records.map(&:to_s)).to eq([
        "example.com. A 3 192.0.2.1",
        "mail.example.com. A 3 192.0.2.3",
        "mail2.example.com. A 3 192.0.2.4",
        "mail3.example.com. A 3 192.0.2.5",
        "ns.example.com. A 3 192.0.2.2",
        "example.com. AAAA 3 2001:db8:10::1",
        "ns.example.com. AAAA 3 2001:db8:10::2",
        "www.example.com. CNAME 3 example.com.",
        "wwwtest.example.com. CNAME 3 www.example.com.",
        "example.com. MX 3 10 mail.example.com.",
        "example.com. MX 3 20 mail2.example.com.",
        "example.com. MX 3 50 mail3.example.com.",
      ])
    end
  end
end


require 'zonesync'
require 'yaml'

describe Zonesync::Provider do
  describe '.call' do
    let(:sample_zone_file_path) { './spec/fixtures/example.com' }
    let(:credentials) { { provider: "Filesystem", path: sample_zone_file_path } }
    let(:records) { described_class.from(credentials).diffable_records }

    context 'types' do
      subject { records.map(&:type) }

      it { is_expected.to eq %w[
        MX MX MX
        A AAAA
        A AAAA
        CNAME CNAME
        A A A
      ] }
    end

    context 'hosts' do
      subject { records.map(&:name) }

      it { is_expected.to eq [
        'example.com.', 'example.com.', 'example.com.',
        'example.com.', 'example.com.',
        'ns.example.com.', 'ns.example.com.',
        'www.example.com.', 'wwwtest.example.com.',
        'mail.example.com.', 'mail2.example.com.', 'mail3.example.com.',
      ] }
    end

    context 'addresses' do
      subject { records.map(&:rdata) }

      it { is_expected.to eq [
        'mail.example.com.', 'mail2.example.com.', 'mail3.example.com.',
        '192.0.2.1', '2001:db8:10::1',
        '192.0.2.2', '2001:db8:10::2',
        'example.com.', 'www.example.com.',
        '192.0.2.3', '192.0.2.4', '192.0.2.5',
      ] }
    end
  end
end


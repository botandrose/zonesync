require "zonesync"

describe Zonesync::Validator do
  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }

  context "with checksum mismatch" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "A:@"
      zonesync_checksum TXT   "BADCHECKSUM"
    RECORDS

    it "raises ChecksumMismatchError by default" do
      operations = []
      expect {
        described_class.call(operations, destination)
      }.to raise_error(Zonesync::ChecksumMismatchError)
    end

    it "does not raise error when force is true" do
      operations = []
      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end

    it "raises ChecksumMismatchError when force is explicitly false" do
      operations = []
      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::ChecksumMismatchError)
    end
  end

  context "without existing checksum" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      zonesync_manifest TXT   "A:@"
    RECORDS

    it "does not raise error regardless of force flag" do
      operations = []
      expect {
        described_class.call(operations, destination, force: false)
      }.not_to raise_error

      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end
  end

  context "with missing manifest" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN example.com.
      $TTL 3600
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
    RECORDS

    it "raises MissingManifestError by default but not with force flag" do
      operations = [[:add, [Zonesync::Record.new(name: "test.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil)]]]

      expect {
        described_class.call(operations, destination, force: false)
      }.to raise_error(Zonesync::MissingManifestError)

      expect {
        described_class.call(operations, destination, force: true)
      }.not_to raise_error
    end
  end
end

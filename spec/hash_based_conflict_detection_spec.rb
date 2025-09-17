require "zonesync"

describe "Hash-based conflict detection" do
  let(:provider) { Zonesync::Provider.from({ provider: "Memory", string: "" }) }

  describe "#hash_based_diffable_records" do
    it "returns matching records when all hashes are found" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil),
        Zonesync::Record.new(name: "mail.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.3", comment: nil)
      ]

      expected_hashes = ["1r81el0", "y2xy9a"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result).to contain_exactly(
        remote_records[0],
        remote_records[1]
      )
    end

    it "ignores unmanaged records" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil),
        Zonesync::Record.new(name: "unmanaged.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.99", comment: nil)
      ]

      expected_hashes = ["1r81el0"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result).to contain_exactly(remote_records[0])
    end

    it "raises ConflictError when managed records are missing" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil)
      ]

      expected_hashes = ["1r81el0", "y2xy9a"]

      expect {
        provider.send(:hash_based_diffable_records, remote_records, expected_hashes)
      }.to raise_error(Zonesync::ConflictError)
    end

    it "raises ConflictError when managed record has been changed remotely" do
      remote_records = [
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.99", comment: nil)
      ]

      expected_hashes = ["1r81el0"]

      expect {
        provider.send(:hash_based_diffable_records, remote_records, expected_hashes)
      }.to raise_error(Zonesync::ConflictError)
    end

    it "sorts the returned records" do
      remote_records = [
        Zonesync::Record.new(name: "zzz.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2", comment: nil),
        Zonesync::Record.new(name: "aaa.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1", comment: nil)
      ]

      expected_hashes = ["hoeh05", "1w6mrp4"]

      result = provider.send(:hash_based_diffable_records, remote_records, expected_hashes)

      expect(result[0].name).to eq("aaa.example.com.")
      expect(result[1].name).to eq("zzz.example.com.")
    end
  end
end
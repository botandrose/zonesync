require "zonesync"

describe Zonesync::CLI do
  context "with --force flag" do
    it "bypasses checksum validation" do
      # Mock the credentials method to return test config
      allow(Zonesync).to receive(:credentials).with(:test_destination).and_return({
        provider: "Memory",
        string: <<~RECORDS
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   "A:@"
          zonesync_checksum TXT   "BADCHECKSUM"
        RECORDS
      })

      # Create a temporary test zonefile
      test_zonefile = "/tmp/test_zonefile"
      File.write(test_zonefile, <<~RECORDS)
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
      RECORDS

      # Test that force flag allows sync despite checksum mismatch
      expect {
        described_class.new.invoke(:sync, [], {
          source: test_zonefile,
          destination: "test_destination",
          dry_run: true,
          force: true
        })
      }.not_to raise_error

      # Clean up
      File.delete(test_zonefile) if File.exist?(test_zonefile)
    end

    it "fails without force flag on checksum mismatch" do
      # Mock the credentials method to return test config
      allow(Zonesync).to receive(:credentials).with(:test_destination).and_return({
        provider: "Memory",
        string: <<~RECORDS
          $ORIGIN example.com.
          $TTL 3600
          @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
          @                 A     192.0.2.1
          zonesync_manifest TXT   "A:@"
          zonesync_checksum TXT   "BADCHECKSUM"
        RECORDS
      })

      # Create a temporary test zonefile
      test_zonefile = "/tmp/test_zonefile"
      File.write(test_zonefile, <<~RECORDS)
        $ORIGIN example.com.
        $TTL 3600
        @    A     192.0.2.1
      RECORDS

      # Test that without force flag, sync fails on checksum mismatch
      expect {
        described_class.new.invoke(:sync, [], {
          source: test_zonefile,
          destination: "test_destination",
          dry_run: true,
          force: false
        })
      }.to raise_error(SystemExit)

      # Clean up
      File.delete(test_zonefile) if File.exist?(test_zonefile)
    end
  end
end
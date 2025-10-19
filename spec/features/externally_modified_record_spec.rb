require "zonesync"

describe "Externally modified tracked record detection" do
  # This test captures a bug where zonesync proposes to ADD a record
  # instead of detecting that a tracked record was modified externally.
  #
  # Scenario:
  # - Manifest tracks ssh.example.com A 173.230.150.20 (hash: 1yj5iyn)
  # - Remote provider has ssh.example.com A 46.224.17.70 (hash: 9vcllt - not tracked)
  # - Local zonefile wants ssh.example.com A 173.230.150.20 (hash: 1yj5iyn)
  #
  # Expected behavior:
  # Zonesync should detect that a tracked record was modified externally
  # and raise an error (or propose to UPDATE it, not ADD it).
  #
  # Actual behavior (BUG):
  # Zonesync proposes to ADD ssh.example.com A 173.230.150.20,
  # which would conflict with the existing (modified) record.

  let(:remote_zone) do
    <<~RECORDS
      $ORIGIN example.com.
      $TTL 1
      @                 SOA   ns.example.com. username.example.com. ( 2007120710 1d 2h 4w 1h )
      @                 A     192.0.2.1
      ssh               A     46.224.17.70
      zonesync_manifest TXT   "1r81el0,1yj5iyn"
    RECORDS
  end

  let(:local_zonefile) do
    <<~RECORDS
      $ORIGIN example.com.
      $TTL 1
      @    A     192.0.2.1
      ssh  A     173.230.150.20
    RECORDS
  end

  let(:remote_provider) { Zonesync::Provider.from({ provider: "Memory", string: remote_zone }) }
  let(:local_provider) { Zonesync::Provider.from({ provider: "Memory", string: local_zonefile }) }

  it "should detect that tracked record was modified externally and raise error" do
    # The manifest says ssh should have hash 1yj5iyn (ssh.example.com. A 1 173.230.150.20)
    # But the remote has ssh with hash 9vcllt (ssh.example.com. A 1 46.224.17.70)
    # This means someone modified the record externally

    # Expected: Should raise ChecksumMismatchError or ConflictError
    # Actual (BUG): Proposes to add the record
    expect {
      operations = remote_provider.diff!(local_provider, force: false)
    }.to raise_error(Zonesync::ChecksumMismatchError)
  end

  context "when force is true" do
    it "should allow the operation to proceed" do
      expect {
        operations = remote_provider.diff!(local_provider, force: true)
      }.not_to raise_error
    end
  end
end

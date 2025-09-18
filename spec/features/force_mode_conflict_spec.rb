require "zonesync"

describe "Force mode with no manifest" do
  # This recreates your exact scenario:
  # - Remote zone has one TXT record (SPF)
  # - Local zonefile has same TXT record PLUS a new different TXT record (Google verification)
  # - No manifest exists
  # - Using --force should succeed, not conflict

  let(:remote_zone) { <<~RECORDS }
    $ORIGIN filmpreservation.org.
    $TTL 3600
    @                 SOA   ns1.dreamhost.com. hostmaster.dreamhost.com. ( 2024010101 14400 3600 1209600 14400 )
    @                 NS    ns1.dreamhost.com.
    @                 NS    ns2.dreamhost.com.
    @                 A     64.90.62.230
    @                 TXT   "v=spf1 include:spf.protection.outlook.com include:networkforgood.com include:networkforgood.org -all"
  RECORDS

  let(:local_zonefile) { <<~RECORDS }
    $ORIGIN filmpreservation.org.
    $TTL 3600
    @    A     64.90.62.230
    @    TXT   "v=spf1 include:spf.protection.outlook.com include:networkforgood.com include:networkforgood.org -all"
    @    TXT   "google-site-verification=rL1dkEFaZtwNvLjL9XKbubgakru5aCxeNMw1xMRM40M"
  RECORDS

  let(:remote_provider) { Zonesync::Provider.from({ provider: "Memory", string: remote_zone }) }
  let(:local_provider) { Zonesync::Provider.from({ provider: "Memory", string: local_zonefile }) }

  it "should not raise ConflictError when adding different TXT record with force=true and no manifest" do
    # Verify no manifest exists
    expect(remote_provider.manifest.existing?).to be false

    # This should NOT raise ConflictError - the validator should allow the addition
    # because we're in force mode and the records are actually different content
    expect {
      operations = remote_provider.diff!(local_provider, force: true)
    }.not_to raise_error

    # Let's also verify what operations would be generated
    operations = remote_provider.diff!(local_provider, force: true)

    # Should generate operations to add the Google verification TXT record and manifests
    add_operations = operations.select { |op| op[0] == :add }
    expect(add_operations.length).to be >= 1

    # One of them should be adding the Google verification TXT record
    google_txt_op = add_operations.find { |op| op[1][0].rdata.include?("google-site-verification") }
    expect(google_txt_op).not_to be_nil
  end

  it "demonstrates the actual error that occurs" do
    # Let's capture exactly what error occurs
    begin
      operations = remote_provider.diff!(local_provider, force: true)
      puts "SUCCESS: Operations generated: #{operations.length}"
      operations.each { |op| puts "  #{op[0]}: #{op[1][0].name} #{op[1][0].type} #{op[1][0].rdata[0..50]}..." }
    rescue => e
      puts "ERROR: #{e.class}: #{e.message}"
      raise e
    end
  end
end
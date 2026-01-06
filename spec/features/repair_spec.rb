# frozen_string_literal: true

require "zonesync"
require "stringio"

describe "zonesync repair" do
  let(:test_zonefile) { "/tmp/test_zonefile_#{$$}" }

  after do
    File.delete(test_zonefile) if File.exist?(test_zonefile)
  end

  def run_repair(local_content:, remote_content:, user_input:)
    File.write(test_zonefile, local_content)

    remote_config = {
      provider: "Memory",
      string: remote_content.dup
    }

    allow(Zonesync).to receive(:credentials).with(:test_destination).and_return(remote_config)

    input = StringIO.new(user_input)
    output = StringIO.new

    # Track remote operations
    remote_operations = { added: [], removed: [], changed: [] }

    # Capture the remote provider and stub its mutation methods
    allow(Zonesync::Provider).to receive(:from).and_wrap_original do |method, config|
      result = method.call(config)
      if config[:provider] == "Memory"
        allow(result).to receive(:add) { |record| remote_operations[:added] << record }
        allow(result).to receive(:remove) { |record| remote_operations[:removed] << record }
        allow(result).to receive(:change) { |old, new| remote_operations[:changed] << [old, new] }
      end
      result
    end

    original_stdin = $stdin
    original_stdout = $stdout
    begin
      $stdin = input
      $stdout = output
      Zonesync::CLI.new.invoke(:repair, [], {
        source: test_zonefile,
        destination: "test_destination"
      })
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
    end

    {
      output: output.string,
      local_content: File.read(test_zonefile),
      remote_operations: remote_operations
    }
  end

  describe "when remote has records not in local zonefile" do
    let(:local_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE
    end

    let(:remote_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
      ZONEFILE
    end

    it "adopts remote record into zonefile when user chooses 'a'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "a\ny\n"
      )

      expect(result[:output]).to include("REMOTE ONLY")
      expect(result[:output]).to include("mail")
      expect(result[:output]).to include("1 record to adopt")
      expect(result[:output]).to include("Repair complete")
      expect(result[:local_content]).to include("mail")
      expect(result[:local_content]).to include("192.0.2.2")
    end

    it "deletes remote record when user chooses 'd'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "d\ny\n"
      )

      expect(result[:output]).to include("REMOTE ONLY")
      expect(result[:output]).to include("1 record to delete")
      expect(result[:output]).to include("Repair complete")
      expect(result[:local_content]).not_to include("mail")
      expect(result[:remote_operations][:removed].length).to eq(1)
      expect(result[:remote_operations][:removed].first.name).to eq("mail.example.com.")
    end

    it "ignores record when user chooses 'i'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "i\ny\n"
      )

      expect(result[:output]).to include("REMOTE ONLY")
      expect(result[:output]).to include("1 record ignored")
      expect(result[:local_content]).not_to include("mail")
    end

    it "aborts when user declines confirmation" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "a\nn\n"
      )

      expect(result[:output]).to include("Apply changes?")
      expect(result[:output]).not_to include("Repair complete")
      expect(result[:local_content]).not_to include("mail")
    end
  end

  describe "when local has records not on remote" do
    let(:local_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
      ZONEFILE
    end

    let(:remote_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE
    end

    it "keeps local and pushes to remote when user chooses 'k'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "k\ny\n"
      )

      expect(result[:output]).to include("LOCAL ONLY")
      expect(result[:output]).to include("mail")
      expect(result[:output]).to include("1 record to push to remote")
      expect(result[:output]).to include("Repair complete")
      # Added records include the mail record plus the manifest
      mail_record = result[:remote_operations][:added].find { |r| r.name == "mail.example.com." }
      expect(mail_record).not_to be_nil
    end

    it "removes from zonefile when user chooses 'r'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "r\ny\n"
      )

      expect(result[:output]).to include("LOCAL ONLY")
      expect(result[:output]).to include("1 record to remove from Zonefile")
      expect(result[:output]).to include("Repair complete")
      expect(result[:local_content]).not_to include("mail")
    end
  end

  describe "when records differ between local and remote" do
    let(:local_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE
    end

    let(:remote_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.99
      ZONEFILE
    end

    it "keeps local when user chooses 'l'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "l\ny\n"
      )

      expect(result[:output]).to include("CHANGED")
      expect(result[:output]).to include("Local:")
      expect(result[:output]).to include("Remote:")
      expect(result[:output]).to include("Repair complete")
      expect(result[:local_content]).to include("192.0.2.1")
      expect(result[:local_content]).not_to include("192.0.2.99")
      expect(result[:remote_operations][:changed].length).to eq(1)
    end

    it "keeps remote when user chooses 'r'" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "r\ny\n"
      )

      expect(result[:output]).to include("CHANGED")
      expect(result[:output]).to include("Repair complete")
      expect(result[:local_content]).to include("192.0.2.99")
    end
  end

  describe "when already in sync" do
    let(:zonefile_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE
    end

    it "reports already in sync" do
      result = run_repair(
        local_content: zonefile_content,
        remote_content: zonefile_content,
        user_input: ""
      )

      expect(result[:output]).to include("Already in sync")
    end
  end

  describe "manifest handling" do
    it "creates manifest after repair when none exists" do
      local_content = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE

      remote_content = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
      ZONEFILE

      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "a\ny\n"
      )

      expect(result[:output]).to include("Creating manifest")
      manifest_record = result[:remote_operations][:added].find { |r| r.manifest? }
      expect(manifest_record).not_to be_nil
      root_hash = Zonesync::RecordHash.generate(
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1")
      )
      mail_hash = Zonesync::RecordHash.generate(
        Zonesync::Record.new(name: "mail.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2")
      )
      expect(manifest_record.rdata).to include(root_hash)
      expect(manifest_record.rdata).to include(mail_hash)
    end

    it "updates manifest after repair when one exists" do
      local_content = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE

      remote_content = <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
        zonesync_manifest  TXT  "oldhash"
      ZONEFILE

      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "a\ny\n"
      )

      expect(result[:output]).to include("Updating manifest")
      manifest_change = result[:remote_operations][:changed].find { |_, new_rec| new_rec.manifest? }
      expect(manifest_change).not_to be_nil
      new_manifest = manifest_change[1]
      root_hash = Zonesync::RecordHash.generate(
        Zonesync::Record.new(name: "example.com.", type: "A", ttl: 3600, rdata: "192.0.2.1")
      )
      mail_hash = Zonesync::RecordHash.generate(
        Zonesync::Record.new(name: "mail.example.com.", type: "A", ttl: 3600, rdata: "192.0.2.2")
      )
      expect(new_manifest.rdata).to include(root_hash)
      expect(new_manifest.rdata).to include(mail_hash)
    end
  end

  describe "when manifest exists but records differ" do
    # This tests the bug where records that exist on both local and remote
    # but weren't in the manifest were incorrectly shown as differences
    let(:local_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
      ZONEFILE
    end

    let(:remote_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
        zonesync_manifest  TXT  "somehash"
      ZONEFILE
    end

    it "reports in sync when records match regardless of manifest" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: ""
      )

      # Even though manifest exists on remote with different hashes,
      # repair should compare ALL records, not just those in manifest
      expect(result[:output]).to include("Already in sync")
    end
  end

  describe "with multiple differences" do
    let(:local_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
      ZONEFILE
    end

    let(:remote_content) do
      <<~ZONEFILE
        $ORIGIN example.com.
        $TTL 3600
        @  A  192.0.2.1
        mail  A  192.0.2.2
        www  CNAME  example.com.
      ZONEFILE
    end

    it "handles multiple records with different choices" do
      result = run_repair(
        local_content: local_content,
        remote_content: remote_content,
        user_input: "a\nd\ny\n"  # adopt mail, delete www, confirm
      )

      expect(result[:output]).to include("Found 2 differences")
      expect(result[:output]).to include("1 record to adopt")
      expect(result[:output]).to include("1 record to delete")
      expect(result[:local_content]).to include("mail")
      expect(result[:local_content]).not_to include("www")
    end
  end
end

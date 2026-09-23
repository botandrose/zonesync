require "zonesync"

describe "Changing a record's type at an existing name" do
  let(:apex_a) { Zonesync::Record.new(name: "deleme.org.", type: "A", ttl: 3600, rdata: "3.83.71.52", comment: nil) }
  let(:cname) { Zonesync::Record.new(name: "ctm-api.deleme.org.", type: "CNAME", ttl: 300, rdata: "d1uj4th7l3tvms.cloudfront.net.", comment: nil) }
  let(:new_a) { Zonesync::Record.new(name: "ctm-api.deleme.org.", type: "A", ttl: 1800, rdata: "3.83.71.52", comment: nil) }

  let(:destination) { Zonesync::Provider.from({ provider: "Memory", string: destination_records }) }
  let(:source) { Zonesync::Provider.from({ provider: "Memory", string: source_records }) }

  def manifest_for(*records)
    records.map { |r| Zonesync::RecordHash.generate(r) }.join(",")
  end

  def applied_operations
    operations = []
    allow(destination).to receive(:add) { |record| operations << [:add, record] }
    allow(destination).to receive(:change) { |old, new| operations << [:change, old, new] }
    allow(destination).to receive(:remove) { |record| operations << [:remove, record] }
    yield
    operations
  end

  context "when an unmanaged CNAME occupies the name of an added A record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @                 SOA   ns.deleme.org. admin.deleme.org. ( 2024010101 14400 3600 1209600 14400 )
      @                 NS    ns.deleme.org.
      @                 A     3.83.71.52
      ctm-api      300  CNAME d1uj4th7l3tvms.cloudfront.net.
      zonesync_manifest TXT   "#{manifest_for(apex_a)}"
    RECORDS

    let(:source_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @            A     3.83.71.52
      ctm-api 1800 A     3.83.71.52
    RECORDS

    it "raises a ConflictError naming the CNAME" do
      expect {
        destination.diff!(source)
      }.to raise_error(Zonesync::ConflictError, /existing: ctm-api\.deleme\.org\. 300 CNAME d1uj4th7l3tvms\.cloudfront\.net\./)
    end

    it "raises a ConflictError even when forced" do
      expect {
        destination.diff!(source, force: true)
      }.to raise_error(Zonesync::ConflictError, /existing: ctm-api\.deleme\.org\. 300 CNAME d1uj4th7l3tvms\.cloudfront\.net\./)
    end
  end

  context "when a managed CNAME is changed to an A record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @                 SOA   ns.deleme.org. admin.deleme.org. ( 2024010101 14400 3600 1209600 14400 )
      @                 NS    ns.deleme.org.
      @                 A     3.83.71.52
      ctm-api      300  CNAME d1uj4th7l3tvms.cloudfront.net.
      zonesync_manifest TXT   "#{manifest_for(apex_a, cname)}"
    RECORDS

    let(:source_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @            A     3.83.71.52
      ctm-api 1800 A     3.83.71.52
    RECORDS

    it "removes the CNAME, adds the A record, and tracks only the A record in the manifest" do
      operations = applied_operations do
        Zonesync::Sync.new(source, destination).call
      end

      old_manifest = destination.manifest.existing
      new_manifest = Zonesync::Record.new(
        name: "zonesync_manifest.deleme.org.",
        type: "TXT",
        ttl: 3600,
        rdata: manifest_for(new_a, apex_a).inspect,
        comment: nil,
      )
      expect(operations).to eq([
        [:remove, cname],
        [:add, new_a],
        [:change, old_manifest, new_manifest],
      ])
    end

    it "prints both the removal and the addition on a dry run" do
      expect {
        Zonesync::Sync.new(source, destination).call(dry_run: true)
      }.to output(
        /Remove ctm-api\.deleme\.org\. CNAME 300 d1uj4th7l3tvms\.cloudfront\.net\..*Add ctm-api\.deleme\.org\. A 1800 3\.83\.71\.52/m
      ).to_stdout_from_any_process
    end
  end

  context "when an added CNAME collides with an unmanaged A record" do
    let(:destination_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @                 SOA   ns.deleme.org. admin.deleme.org. ( 2024010101 14400 3600 1209600 14400 )
      @                 NS    ns.deleme.org.
      @                 A     3.83.71.52
      ctm-api     1800  A     3.83.71.52
      zonesync_manifest TXT   "#{manifest_for(apex_a)}"
    RECORDS

    let(:source_records) { <<~RECORDS }
      $ORIGIN deleme.org.
      $TTL 3600
      @       A     3.83.71.52
      ctm-api CNAME d1uj4th7l3tvms.cloudfront.net.
    RECORDS

    it "raises a ConflictError naming the A record" do
      expect {
        destination.diff!(source)
      }.to raise_error(Zonesync::ConflictError, /existing: ctm-api\.deleme\.org\. 1800 A 3\.83\.71\.52/)
    end

    it "raises a ConflictError even when forced" do
      expect {
        destination.diff!(source, force: true)
      }.to raise_error(Zonesync::ConflictError, /existing: ctm-api\.deleme\.org\. 1800 A 3\.83\.71\.52/)
    end
  end
end

# Architecture: Zonesync

Zonesync synchronizes DNS zone files with DNS providers (Cloudflare, Route53). It treats DNS configuration as code — you edit a local Zonefile, and zonesync pushes the changes to your DNS provider, tracking what it manages via a manifest record.

## The Three Flows

Everything in zonesync serves one of three operations: **sync**, **generate**, or **repair**.

### Sync

The primary operation. Pushes local Zonefile changes to a DNS provider.

```
  +-----------+      +----------+
  | Zonefile  |      | Provider |
  | (local)   |      | (remote) |
  +-----+-----+      +-----+----+
        |                   |
        v                   v
   parse into          fetch & parse
   Record[]             into Record[]
        |                   |
        |             filter by Manifest
        |              (managed only)
        |                   |
        v                   v
      source            destination
     records         diffable_records
        \                 /
         \               /
          v             v
       +---------------+
       |  Diff Engine  |
       +-------+-------+
               |
               v
        Operations[]
     (add, remove, change)
               |
               v
       +---------------+
       |   Validator   |
       +-------+-------+
               |
          pass | fail
          /         \
         v           v
   Apply ops     Raise error
   via Provider  (Conflict,
   API calls     Checksum, etc.)
               |
               v
       Update Manifest
```

**Call chain:**

    Zonesync.call
      -> Sync#call(dry_run:, force:)
           -> destination.diff!(source, force:)
                -> Provider#diffable_records  (filter by Manifest)
                -> Diff.call(destination_records, source_records)
                -> Validator.call(operations, ..., force:)
           -> compare & sync Manifest record
           -> handle Checksum transition (v1 -> v2)
           -> for each operation:
                Logger.log(op)
                destination.add / remove / change

### Generate

Pulls current DNS state and writes it as a local Zonefile. Simple one-liner.

```
  +----------+         +----------+
  | Provider |  read   | Zonefile |
  | (remote) | ------> | (local)  |
  +----------+  write  +----------+
```

**Call chain:**

    Zonesync.generate
      -> Generate#call
           -> destination.write(source.read)

### Repair

Interactive mode for resolving drift. Unlike sync, repair shows ALL differences (not just managed records) and lets the user decide what to do with each one.

```
  +----------+      +----------+
  | Zonefile |      | Provider |
  | (local)  |      | (remote) |
  +----+-----+      +-----+----+
       |                   |
       v                   v
    Record[]            Record[]
       \                  /
        v                v
      +------------------+
      |  Diff (raw, no   |
      |  manifest filter)|
      +--------+---------+
               |
               v
    For each difference:
    +---------------------------------+
    | Remote only:                    |
    |   [a]dopt  [d]elete  [i]gnore  |
    |                                 |
    | Local only:                     |
    |   [k]eep   [r]emove  [i]gnore  |
    |                                 |
    | Changed:                        |
    |   [l]ocal  [r]emote  [i]gnore  |
    +---------------------------------+
               |
               v
       Show summary
       Confirm with user
               |
               v
    Apply chosen actions
    Update manifest
```

**Call chain:**

    Zonesync.repair
      -> Repair#call(input:, output:)
           -> Diff.call (without manifest filtering)
           -> prompt user per difference
           -> apply: Provider.add/remove/change + Zonefile edits
           -> update Manifest, remove old Checksum

## Provider Interface

All DNS sources implement the same interface. The base class (`Provider`) provides shared logic; subclasses implement I/O.

```
                    Provider (base)
                   /    |    \      \
                  /     |     \      \
          Cloudflare  Route53  Filesystem  Memory
```

**Interface:**

    read()                -> String        # raw zone content
    write(string)         -> void          # write zone content
    add(record)           -> void          # create one record
    remove(record)        -> void          # delete one record
    change(old, new)      -> void          # modify one record
    records()             -> Record[]      # parsed, cached
    diffable_records()    -> Record[]      # filtered by manifest
    manifest()            -> Manifest
    diff!(other, force:)  -> Operation[]   # diff + validate
    diff(other)           -> Operation[]   # diff only

**Cloudflare** talks JSON to the Cloudflare API. Synthesizes a fake SOA (Cloudflare doesn't expose one). Handles MX priority splitting and proxy toggle tracking via `ProxiedSupport` module that extends Record instances with `cf_tags=cf-proxied:true/false` in comments.

**Route53** talks XML to the AWS API with Signature V4 signing. Route53 groups records into sets (same name+type) treated atomically — removing one record from a multi-value set requires deleting the whole set and recreating the rest. Splits TXT records at the 255-char boundary.

**Filesystem** reads/writes a local file. **Memory** holds a string in a hash (for tests).

Both API providers use the `HTTP` struct — a thin Net::HTTP wrapper with `before_request`/`after_response` hooks for auth and signing.

## Safety Mechanisms

### Manifest

A TXT record (`zonesync_manifest`) on the DNS provider that lists which records zonesync manages. This is the boundary between "ours" and "theirs" — only managed records participate in sync diffs.

Two formats:

    V1: "A:@,mail;CNAME:www;MX:@ 10,@ 20"     # type-grouped shorthand
    V2: "1r81el0,60oib3,ky0g92,9pp0kg"          # per-record CRC32 hashes

V2 hashes are generated by `RecordHash` — CRC32 of `"name:type:ttl:rdata"` in base36.

### Validator

Runs before any operations are applied. Skipped with `--force`.

    Check 1: Manifest exists?
              No + no operations -> MissingManifestError
              (first sync must explicitly add the manifest)

    Check 2: V1 checksum matches?
              No -> ChecksumMismatchError
              (someone changed managed records outside zonesync)

    Check 3: V2 manifest integrity?
              Expected hashes missing from actual records -> ChecksumMismatchError
              (per-record detection of external modifications)

    Check 4: Conflicts?
              Adding a record where an untracked record exists
              at same name+type -> ConflictError

### Error Types

    ConflictError          - untracked record would be overwritten
    ChecksumMismatchError  - external changes detected (v1 or v2)
    MissingManifestError   - no manifest on first sync
    DuplicateRecordError   - provider says record already exists

## Data Model

**Record** — immutable struct: `name`, `type`, `ttl`, `rdata`, `comment`. Knows how to compare itself (`identical_to?`, `conflicts_with?`), identify meta-records (`manifest?`, `checksum?`), and render as a zone file line (`to_s`). Sorting puts SOA first, then alphabetical by type/name/rdata/ttl.

**Zonefile** — parses zone strings into Record arrays via a Treetop PEG grammar (`zonefile.treetop`). The `Parser` module wraps the grammar, processing `$ORIGIN`/`$TTL` variables, qualifying relative hostnames, and handling implicit name inheritance.

**Diff** — groups records by primary key (name+type), then compares within each group. Single-record groups emit a change if different. Multi-record groups use set difference. Sorts output with removes first.

## Configuration

Provider credentials come from Rails encrypted credentials (`config/credentials.yml.enc`):

    zonesync:
      source:
        provider: filesystem
        path: Zonefile
      destination:
        provider: cloudflare   # or route53
        zone_id: abc123
        token: secret

## File Listing

    lib/zonesync.rb                       Entry point, provider construction
    lib/zonesync/cli.rb                   Thor CLI
    lib/zonesync/rake.rb                  Rake task
    lib/zonesync/sync.rb                  Sync orchestration
    lib/zonesync/generate.rb              Zone generation
    lib/zonesync/repair.rb                Interactive repair
    lib/zonesync/provider.rb              Base + Filesystem + Memory providers
    lib/zonesync/cloudflare.rb            Cloudflare provider
    lib/zonesync/cloudflare/proxied_support.rb  Proxy toggle tracking
    lib/zonesync/route53.rb               Route53 provider
    lib/zonesync/record.rb                DNS record struct
    lib/zonesync/zonefile.rb              Zone file loader
    lib/zonesync/parser.rb                Treetop grammar wrapper
    lib/zonesync/zonefile.treetop         PEG grammar (RFC 1035)
    lib/zonesync/diff.rb                  Diff engine
    lib/zonesync/manifest.rb              Manifest tracking (v1 + v2)
    lib/zonesync/validator.rb             Pre-sync safety checks
    lib/zonesync/record_hash.rb           Per-record CRC32 hashing
    lib/zonesync/http.rb                  HTTP client with hooks
    lib/zonesync/logger.rb                Operation logging
    lib/zonesync/errors.rb                Custom exceptions
    lib/zonesync/version.rb               Version constant

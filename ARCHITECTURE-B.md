# Architecture: Zonesync

Zonesync synchronizes DNS zone files with DNS providers (Cloudflare, Route53). It treats DNS configuration as code — you edit a local Zonefile, and zonesync pushes the changes to your DNS provider, tracking what it manages via a manifest record.

## File Tree

```
lib/zonesync/
  cli.rb              # Thor CLI commands
  rake.rb             # Rake task definition
  sync.rb             # Sync orchestration
  generate.rb         # Zone generation
  repair.rb           # Interactive repair
  provider.rb         # Base provider + Filesystem + Memory
  cloudflare.rb       # Cloudflare provider
  cloudflare/
    proxied_support.rb # Cloudflare proxy toggle handling
  route53.rb          # Route53 provider
  record.rb           # DNS record struct
  zonefile.rb         # Zone file loader
  parser.rb           # Treetop grammar wrapper
  zonefile.treetop    # PEG grammar for RFC 1035 zone files
  diff.rb             # Diff engine
  manifest.rb         # Manifest tracking (v1 + v2)
  validator.rb        # Pre-sync safety checks
  record_hash.rb      # Per-record CRC32 hashing
  http.rb             # HTTP client with hooks
  logger.rb           # Operation logging
  errors.rb           # Custom exception classes
  version.rb          # Gem version constant
```

## Components

### `Zonesync` (module) — `lib/zonesync.rb`

**Purpose:** Top-level API and provider construction.

**Key methods:**
- `call(source:, destination:, dry_run:, force:)` — builds providers, runs Sync
- `generate(source:, destination:)` — builds providers, runs Generate
- `repair(source:, destination:)` — builds providers, runs Repair
- `credentials(key)` — reads Rails encrypted credentials for provider config

**Collaborators:** `Sync`, `Generate`, `Repair`, `Provider` subclasses

---

### `CLI` — `lib/zonesync/cli.rb`

**Purpose:** Thor-based command-line interface.

**Commands:**
- `sync` (default) — options: `--source`, `--destination`, `--dry-run`, `--force`
- `generate` — generates local Zonefile from provider
- `repair` — interactive drift resolution

**Collaborators:** `Zonesync` module (delegates all work)

---

### `Sync` — `lib/zonesync/sync.rb`

**Purpose:** Orchestrates synchronization from source to destination provider.

**Key methods:**
- `call(dry_run:, force:)` — computes diff, syncs manifest/checksum, applies operations

**Algorithm:**
1. `destination.diff!(source, force:)` to get operations
2. Compare source vs destination manifest; add manifest update if needed
3. Handle v1→v2 checksum transition if applicable
4. Log and apply each operation (unless dry_run)

**Collaborators:** `Provider`, `Manifest`, `Logger`

---

### `Generate` — `lib/zonesync/generate.rb`

**Purpose:** Pulls zone from a provider and writes it locally.

**Key methods:**
- `call` — `destination.write(source.read)`

**Collaborators:** `Provider`

---

### `Repair` — `lib/zonesync/repair.rb`

**Purpose:** Interactive resolution of drift between local Zonefile and remote DNS.

**Key methods:**
- `call(input:, output:)` — walks user through each difference, applies chosen actions

**Actions per difference type:**
- Remote only: adopt / delete / ignore
- Local only: keep (push) / remove / ignore
- Changed: pick local / pick remote / ignore

**Collaborators:** `Provider`, `Diff`, `Manifest`

---

### `Provider` (base) — `lib/zonesync/provider.rb`

**Purpose:** Abstract interface for DNS record sources.

**Key methods:**
- `read` / `write(string)` — raw zone string I/O (subclass responsibility)
- `add(record)` / `remove(record)` / `change(old, new)` — record-level mutations
- `records` — lazily parses zone string into `Record` array
- `diffable_records` — filters records to only those tracked by manifest
- `manifest` — returns `Manifest` instance for this provider
- `diff!(other, force:)` — computes diff and runs validation
- `diff(other)` — raw diff without validation

**Subclasses:** `Cloudflare`, `Route53`, `Filesystem`, `Memory`

---

### `Cloudflare` — `lib/zonesync/cloudflare.rb`

**Purpose:** Cloudflare DNS API provider.

**Auth:** Bearer token or email + API key.

**Key methods:**
- `read` — fetches all records via API, synthesizes SOA, returns zone string
- `add` / `remove` / `change` — API calls (POST / DELETE / PATCH)
- `find_record_id(record)` — looks up Cloudflare record ID by matching content
- `to_hash(record)` / `to_record(attrs)` — converts between Record and API format

**Notable behavior:**
- Synthesizes a fake SOA (Cloudflare doesn't expose one via API)
- Splits MX priority out of rdata for API format
- Catches duplicate error code 81058
- Custom `diff` extends source records with `ProxiedSupport`

**Collaborators:** `HTTP`, `ProxiedSupport`, `Record`

---

### `ProxiedSupport` — `lib/zonesync/cloudflare/proxied_support.rb`

**Purpose:** Module mixed into Record instances to track Cloudflare proxy toggle.

**Mechanism:** Parses `cf_tags=cf-proxied:true/false` from record comment field. Overrides `to_h`, `==`, `eql?`, `hash`, and `to_s` to include proxy state.

**Collaborators:** `Record`

---

### `Route53` — `lib/zonesync/route53.rb`

**Purpose:** AWS Route53 DNS API provider.

**Auth:** AWS access key + secret key, hosted zone ID.

**Key methods:**
- `read` — fetches record sets via XML API, converts to zone string
- `add` — CREATE or UPSERT depending on existing record set
- `remove` — DELETE if sole record in set; otherwise DELETE set + CREATE remainder
- `change` — UPSERT to replace record in set
- `rdata_for_api(record)` — splits TXT records at 255-char boundary
- `sign(request)` — AWS Signature Version 4

**Notable behavior:**
- Route53 groups records into sets (same name+type) and treats them atomically
- Invalidates read cache after any write operation

**Collaborators:** `HTTP`, `Record`

---

### `Filesystem` — `lib/zonesync/provider.rb`

**Purpose:** Local zone file provider. Reads/writes a file at a configured path.

---

### `Memory` — `lib/zonesync/provider.rb`

**Purpose:** In-memory provider for testing. Stores zone content in a config hash.

---

### `Record` — `lib/zonesync/record.rb`

**Purpose:** Immutable DNS record representation.

**Fields:** `name`, `type`, `ttl`, `rdata`, `comment`

**Key methods:**
- `identical_to?(other)` — exact match on name/type/ttl/rdata
- `conflicts_with?(other)` — detects illegal overlaps (e.g. duplicate CNAME, same MX priority)
- `manifest?` / `checksum?` — identifies zonesync meta-records
- `short_name(origin)` — strips origin suffix (e.g. `www.example.com.` → `www`)
- `<=>` — sort order: SOA first, then by type/name/rdata/ttl
- `to_s` — zone file line format

**Collaborators:** used by everything

---

### `Zonefile` — `lib/zonesync/zonefile.rb`

**Purpose:** Parses zone file strings into Record arrays.

**Key methods:**
- `load(zone_string)` — parses via Parser, returns Zonefile instance
- `ensure_soa(zone_string)` — injects dummy SOA if missing
- `records` — parsed Record objects
- `origin` — zone origin from SOA or $ORIGIN

**Collaborators:** `Parser`, `Record`

---

### `Parser` — `lib/zonesync/parser.rb`

**Purpose:** Wraps Treetop PEG grammar (`zonefile.treetop`) for RFC 1035 zone files.

**Key methods:**
- `parse(zone_string)` — returns Zone instance

**Zone class:** processes `$ORIGIN`/`$TTL` variables, qualifies relative hostnames, handles implicit name inheritance.

---

### `Diff` — `lib/zonesync/diff.rb`

**Purpose:** Computes add/remove/change operations between two record sets.

**Key methods:**
- `call(from, to)` — returns operations array

**Algorithm:**
- Groups records by primary key (name + type)
- Single-record groups: emits change if different
- Multi-record groups: uses set difference for adds/removes
- Missing keys: emit add or remove for entire group
- Sorts: removes first, reverse alphabetical

**Collaborators:** `Record`

---

### `Manifest` — `lib/zonesync/manifest.rb`

**Purpose:** Tracks which records zonesync manages via a special TXT record (`zonesync_manifest`).

**Formats:**
- **V1:** `"A:@,mail;CNAME:www;MX:@ 10,@ 20"` — type-grouped shorthand
- **V2:** `"1r81el0,60oib3,ky0g92"` — comma-separated per-record hashes

**Key methods:**
- `existing` / `existing?` — finds manifest on remote
- `generate` — generates v2 manifest record
- `diffable?(record)` — is this record managed by zonesync?
- `matches?(record)` — does record appear in manifest? (works with both formats)
- `v1_format?` / `v2_format?` — detects format

**Collaborators:** `RecordHash`, `Record`

---

### `Validator` — `lib/zonesync/validator.rb`

**Purpose:** Pre-sync safety checks. All checks skipped with `--force`.

**Checks:**
1. Missing manifest on first sync → `MissingManifestError`
2. V1 checksum mismatch → `ChecksumMismatchError`
3. V2 manifest integrity (expected hashes vs actual) → `ChecksumMismatchError`
4. Conflict detection (untracked record at same name+type) → `ConflictError`

**Collaborators:** `Manifest`, `Record`

---

### `RecordHash` — `lib/zonesync/record_hash.rb`

**Purpose:** Generates 6-character base36 hash (CRC32) of `"name:type:ttl:rdata"` for v2 manifest.

**Key methods:**
- `generate(record)` — returns hash string

---

### `HTTP` — `lib/zonesync/http.rb`

**Purpose:** HTTP client wrapper with hook support.

**Key methods:**
- `get` / `post` / `patch` / `delete` — standard HTTP methods
- `before_request` hook — used for auth headers and request signing
- `after_response` hook — used for response processing

**Behavior:** JSON auto-serialization, raises on non-2xx responses.

**Collaborators:** used by `Cloudflare`, `Route53`

---

### `Logger` — `lib/zonesync/logger.rb`

**Purpose:** Logs operations to STDOUT and optionally to `log/zonesync.log`.

**Key methods:**
- `log(method, records, dry_run:)` — formats and outputs operation details

---

### `Errors` — `lib/zonesync/errors.rb`

| Error Class | Raised When |
|---|---|
| `ConflictError` | Untracked record would be overwritten |
| `ChecksumMismatchError` | External changes detected (v1 or v2) |
| `MissingManifestError` | No manifest exists on first sync |
| `DuplicateRecordError` | Provider reports record already exists |

## Cross-Cutting Concerns

### Manifest Versioning

The system supports two manifest formats. V1 uses type-grouped shorthand names; v2 uses per-record CRC32 hashes. The sync process handles transitions from v1 to v2 automatically, removing the old checksum record when upgrading.

### Configuration

Provider credentials come from Rails encrypted credentials (`config/credentials.yml.enc` decrypted with `config/master.key` or `RAILS_MASTER_KEY`). Each credential set specifies a `provider` key that determines which Provider subclass to instantiate.

### Caching

- Cloudflare caches all fetched records in memory
- Route53 caches read results, invalidating after writes
- Zonefile lazily parses and caches Record arrays

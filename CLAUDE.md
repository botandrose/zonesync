# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zonesync is a Ruby gem that synchronizes DNS zone files with DNS providers (Cloudflare, Route53). It treats DNS configuration as code, enabling version control and CI/CD workflows for DNS records.

## Commands

### Development Commands
- `bundle install` - Install dependencies
- `bundle exec rake` - Run all tests (default task)
- `bundle exec rspec` - Run RSpec tests
- `bundle exec rspec spec/path/to/specific_spec.rb` - Run a single test file
- `bundle exec rspec spec/path/to/specific_spec.rb:123` - Run a specific test at line 123

### Application Commands
- `bundle exec zonesync` - Sync Zonefile to configured DNS provider
- `bundle exec zonesync --dry-run` - Preview changes without applying them
- `bundle exec zonesync --force` - Force sync ignoring checksum mismatches
- `bundle exec zonesync generate` - Generate Zonefile from DNS provider

### Type Checking (Sorbet)
- `bundle exec srb tc` - Run Sorbet type checker
- `bundle exec tapioca gem` - Generate RBI files for gems

## Architecture

### Core Components

**Provider Pattern**: Abstract base class `Provider` with concrete implementations:
- `Cloudflare` - Cloudflare DNS API integration
- `Route53` (AWS) - Route53 DNS API integration
- `Filesystem` - Local zone file operations
- `Memory` - In-memory provider for testing

**Key Classes**:
- `Sync` - Orchestrates synchronization between source and destination providers
- `Generate` - Generates zone files from DNS providers
- `Record` - Represents DNS records with type, name, content, TTL
- `Zonefile` - Parses and generates RFC-compliant zone files
- `Diff` - Calculates differences between record sets
- `Manifest` - Tracks which records are managed by zonesync
- `Validator` - Validates operations and handles conflicts

### Data Flow

1. **Sync Process**: `Zonefile` → `Provider.diff!()` → `operations[]` → `destination.apply()`
2. **Generate Process**: DNS Provider → `Zonefile.generate()` → local file
3. **Validation**: Checksum verification prevents conflicting external changes
4. **Manifest**: TXT records track zonesync-managed records vs external ones

### Safety Mechanisms

- **Checksum verification**: Detects external changes to managed records
- **Manifest tracking**: Distinguishes zonesync-managed vs external records
- **Force mode**: Bypass safety checks when needed
- **Dry-run mode**: Preview changes without applying them

### Configuration

Credentials stored in Rails-style encrypted configuration:
- `config/credentials.yml.enc` - Encrypted credentials file
- `config/master.key` - Encryption key
- `RAILS_MASTER_KEY` env var - Alternative key source

## Testing

- **RSpec** for testing framework
- **WebMock** for HTTP request stubbing
- **Feature specs** in `spec/features/` test end-to-end workflows
- **Unit specs** test individual classes and methods
- All tests should pass before committing changes

## Type Safety

Uses **Sorbet** for gradual typing:
- All files have `# typed: strict` or similar headers
- Method signatures use `sig { ... }` blocks
- `extend T::Sig` enables signature checking
- RBI files in `sorbet/rbi/` define external gem types

## Error Handling

Custom exceptions in `lib/zonesync/errors.rb`:
- `ConflictError` - Record conflicts
- `ChecksumMismatchError` - External changes detected
- `MissingManifestError` - Missing manifest record
- `DuplicateRecordError` - Duplicate record handling
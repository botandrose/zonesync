# Zonesync

[![CI Status](https://github.com/botandrose/zonesync/workflows/CI/badge.svg?branch=master)](https://github.com/botandrose/zonesync/actions?query=workflow%3ACI+branch%3Amaster)

Sync your DNS host with your DNS zone file, making it easy to version your zone file and sync changes.

## Why?

Configuration management is important, and switched-on technical types now agree that "configuration is code". This means that your DNS configuration should be treated with the same degree of respect you would give to any other code you would write.

In order to live up to this standard, there needs to be an easy way to manage your DNS host file in a SCM tool like Git, allowing you to feed it into a continuous integration pipeline. This library enables this very ideal, making DNS management no different to source code management.

## How?

### Install

Add `zonesync` to your Gemfile:

```ruby
source 'https://rubygems.org'

gem 'zonesync'
```

or run:

`gem install zonesync`

### DNS zone file

The following is an example DNS zone file for `example.com`:

```
$ORIGIN example.com.
$TTL 1h
example.com.  IN  SOA  ns.example.com. username.example.com. (2007120710; 1d; 2h; 4w; 1h)
example.com.  NS    ns
example.com.  NS    ns.somewhere.example.
example.com.  MX    10 mail.example.com.
@             MX    20 mail2.example.com.
@             MX    50 mail3
example.com.  A     192.0.2.1
              AAAA  2001:db8:10::1
ns            A     192.0.2.2
              AAAA  2001:db8:10::2
www           CNAME example.com.
wwwtest       CNAME www
mail          A     192.0.2.3
mail2         A     192.0.2.4
mail3         A     192.0.2.5
```

### DNS Host

We need to tell `zonesync` about our DNS host by building a small YAML file. The structure of this file will depend on your DNS host, so here are some examples:

**Cloudflare**

```
provider: Cloudflare
email: <CLOUDFLARE_EMAIL>
key: <CLOUDFLARE_API_KEY>
```

**Route 53**

```
provider: AWS
aws_access_key_id: <AWS_ACCESS_KEY_ID>
aws_secret_access_key: <AWS_SECRET_ACCESS_KEY>
```

### Usage

#### CLI

```
$ bundle exec zonesync
```
```
$ bundle exec zonesync --dry-run # log to STDOUT but don't actually perform the sync
```
```
$ bundle exec zonesync generate # generate a Zonefile from the configured provider
```
#### Ruby

Assuming your zone file lives in `hostfile.txt` and your DNS provider credentials are configured in `provider.yml`:

```ruby
require 'zonesync'
Zonesync.call(zonefile: 'hostfile.txt', credentials: YAML.load('provider.yml'))
```


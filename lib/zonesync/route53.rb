require "zonesync/record"
require "zonesync/http"
require "rexml/document"

module Zonesync
  class Route53 < Provider
    def read
      doc = REXML::Document.new(http.get(nil))
      records = doc.elements.collect("*/ResourceRecordSets/ResourceRecordSet") do |record_set|
        to_records(record_set)
      end.flatten.sort
      records.map(&:to_s).join("\n") + "\n"
    end

    def remove(record)
      change_record("DELETE", record)
    end

    def change(old_record, new_record)
      remove(old_record)
      add(new_record)
    end

    def add(record)
      change_record("CREATE", record)
    end

    private

    def change_record(action, record)
      http.post(nil, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
          <ChangeBatch>
            <Changes>
              <Change>
                <Action>#{action}</Action>
                <ResourceRecordSet>
                  <Name>#{record[:name]}</Name>
                  <Type>#{record[:type]}</Type>
                  <TTL>#{record[:ttl]}</TTL>
                  <ResourceRecords>
                    <ResourceRecord>
                      <Value>#{record[:rdata]}</Value>
                    </ResourceRecord>
                  </ResourceRecords>
                </ResourceRecordSet>
              </Change>
            </Changes>
          </ChangeBatch>
        </ChangeResourceRecordSetsRequest>
      XML
    end

    def to_records(el)
      el.elements.collect("ResourceRecords/ResourceRecord") do |rr|
        name = normalize_trailing_period(get_value(el, "Name"))
        type = get_value(el, "Type")
        rdata = get_value(rr, "Value")

        record = Record.new(
          name,
          type,
          get_value(el, "TTL"),
          rdata,
          nil, # Route 53 does not have a direct comment field
        )
      end
    end

    def get_value el, field
      el.elements[field].text.gsub(/\\(\d{3})/) { $1.to_i(8).chr } # unescape octal
    end

    def from_record(record)
      {
        Name: normalize_trailing_period(record[:name]),
        Type: record[:type],
        TTL: record[:ttl],
        ResourceRecords: record[:rdata].split(",").map { |value| { Value: value } }
      }
    end

    def normalize_trailing_period(value)
      value =~ /\.$/ ? value : value + "."
    end

    def http
      return @http if @http
      @http = HTTP.new("https://route53.amazonaws.com/2013-04-01/hostedzone/#{credentials.fetch(:hosted_zone_id)}/rrset")
      @http.before_request do |request, uri, body|
        request["Content-Type"] = "application/xml"
        request["X-Amz-Date"] = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        request["Authorization"] = sign_request(request.method, uri, body)
      end
      @http
    end

    def sign_request(method, uri, body)
      service = "route53"
      date = Time.now.utc.strftime("%Y%m%d")
      amz_date = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      canonical_uri = uri.path
      canonical_querystring = uri.query.to_s
      canonical_headers = "host:#{uri.host}\n" + "x-amz-date:#{amz_date}\n"
      signed_headers = "host;x-amz-date"
      payload_hash = OpenSSL::Digest::SHA256.hexdigest(body || "")
      canonical_request = [
        method,
        canonical_uri,
        canonical_querystring,
        canonical_headers,
        signed_headers,
        payload_hash
      ].join("\n")

      algorithm = "AWS4-HMAC-SHA256"
      credential_scope = "#{date}/#{credentials.fetch(:aws_region)}/#{service}/aws4_request"
      string_to_sign = [
        algorithm,
        amz_date,
        credential_scope,
        OpenSSL::Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      signing_key = get_signature_key(credentials.fetch(:aws_secret_access_key), date, credentials.fetch(:aws_region), service)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      "#{algorithm} Credential=#{credentials.fetch(:aws_access_key_id)}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
    end

    def get_signature_key(key, date_stamp, region_name, service_name)
      k_date = OpenSSL::HMAC.digest("SHA256", "AWS4" + key, date_stamp)
      k_region = OpenSSL::HMAC.digest("SHA256", k_date, region_name)
      k_service = OpenSSL::HMAC.digest("SHA256", k_region, service_name)
      OpenSSL::HMAC.digest("SHA256", k_service, "aws4_request")
    end
  end
end


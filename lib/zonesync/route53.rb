# frozen_string_literal: true

require "zonesync/record"
require "zonesync/http"
require "rexml/document"
require "erb"

module Zonesync
  class Route53 < Provider
    def read
      @read ||= begin
        doc = REXML::Document.new(http.get(""))
        records = doc.elements.collect("*/ResourceRecordSets/ResourceRecordSet") do |record_set|
          to_records(record_set)
        end.flatten.sort
        records.map(&:to_s).join("\n") + "\n"
      end
    end

    def remove(record)
      # Route53 requires all records with the same name/type to be managed together as a record set
      existing_records = records.select do |r|
        r.name == record.name && r.type == record.type
      end

      if existing_records.length == 1
        change_record("DELETE", record)
      else
        remaining_records = existing_records.reject { |r| r == record }

        grouped = [
          [existing_records, "DELETE"],
          *(remaining_records.any? ? [[remaining_records, "CREATE"]] : [])
        ]

        http.post("", ERB.new(<<~XML, trim_mode: "-").result(binding))
          <?xml version="1.0" encoding="UTF-8"?>
          <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
            <ChangeBatch>
              <Changes>
                <%- grouped.each do |records_list, action| -%>
                <%- records_grouped = records_list.group_by { |r| [r.name, r.type, r.ttl] } -%>
                <%- records_grouped.each do |(name, type, ttl), group_records| -%>
                <Change>
                  <Action><%= action %></Action>
                  <ResourceRecordSet>
                    <Name><%= name %></Name>
                    <Type><%= type %></Type>
                    <TTL><%= ttl %></TTL>
                    <ResourceRecords>
                      <%- group_records.each do |group_record| -%>
                      <ResourceRecord>
                        <Value><%= rdata_for_api(group_record) %></Value>
                      </ResourceRecord>
                      <%- end -%>
                    </ResourceRecords>
                  </ResourceRecordSet>
                </Change>
                <%- end -%>
                <%- end -%>
              </Changes>
            </ChangeBatch>
          </ChangeResourceRecordSetsRequest>
        XML

        invalidate_cache!
      end
    end

    def change(old_record, new_record)
      remove(old_record)
      add(new_record)
    end

    def add(record)
      add_with_duplicate_handling(record) do
        begin
          # Route53 requires all records with the same name/type to be in a single record set
          existing_records = records.select do |r|
            r.name == record.name && r.type == record.type
          end
          all_records = (existing_records + [record]).uniq

          action = existing_records.empty? ? "CREATE" : "UPSERT"
          change_records(action, all_records)
          invalidate_cache! if existing_records.any?
        rescue RuntimeError => e
          if e.message.include?("RRSet already exists")
            raise DuplicateRecordError.new(record, "Route53 duplicate record error")
          else
            raise
          end
        end
      end
    end

    private

    def invalidate_cache!
      @read = nil
      @zonefile = nil
    end

    def change_record(action, record)
      http.post("", <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
          <ChangeBatch>
            <Changes>
              <Change>
                <Action>#{action}</Action>
                <ResourceRecordSet>
                  <Name>#{record.name}</Name>
                  <Type>#{record.type}</Type>
                  <TTL>#{record.ttl}</TTL>
                  <ResourceRecords>
                    <ResourceRecord>
                      <Value>#{rdata_for_api(record)}</Value>
                    </ResourceRecord>
                  </ResourceRecords>
                </ResourceRecordSet>
              </Change>
            </Changes>
          </ChangeBatch>
        </ChangeResourceRecordSetsRequest>
      XML
    end

    def change_records(action, records_list)
      # Group records by name and type to handle multiple values
      grouped = records_list.group_by { |r| [r.name, r.type, r.ttl] }

      http.post("", ERB.new(<<~XML, trim_mode: "-").result(binding))
        <?xml version="1.0" encoding="UTF-8"?>
        <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
          <ChangeBatch>
            <Changes>
              <%- grouped.each do |(name, type, ttl), records| -%>
              <Change>
                <Action><%= action %></Action>
                <ResourceRecordSet>
                  <Name><%= name %></Name>
                  <Type><%= type %></Type>
                  <TTL><%= ttl %></TTL>
                  <ResourceRecords>
                    <%- records.each do |record| -%>
                    <ResourceRecord>
                      <Value><%= rdata_for_api(record) %></Value>
                    </ResourceRecord>
                    <%- end -%>
                  </ResourceRecords>
                </ResourceRecordSet>
              </Change>
              <%- end -%>
            </Changes>
          </ChangeBatch>
        </ChangeResourceRecordSetsRequest>
      XML
    end

    def rdata_for_api(record)
      return record.rdata unless record.type == "TXT"

      # DNS TXT strings have a 255-character limit per quoted string.
      # Split any single quoted string that exceeds this limit.
      record.rdata.scan(/"([^"]*)"/).flatten.flat_map { |s|
        s.scan(/.{1,255}/)
      }.map { |s| %("#{s}") }.join(" ")
    end

    def to_records(el)
      el.elements.collect("ResourceRecords/ResourceRecord") do |rr|
        name = normalize_trailing_period(get_value(el, "Name"))
        type = get_value(el, "Type")
        ttl = get_value(el, "TTL")
        rdata = get_value(rr, "Value")
        rdata = normalize_txt_rdata(rdata) if type == "TXT"

        record = Record.new(
          name: name,
          type: type,
          ttl: ttl,
          rdata: rdata,
          comment: nil, # Route 53 does not have a direct comment field
        )
      end
    end

    def get_value(el, field)
      el.elements[field].text.gsub(/\\(\d{3})/) { $1.to_i(8).chr } # unescape octal
    end

    def normalize_txt_rdata(rdata)
      # Route53 splits long TXT strings at 255 chars. Join them back into a
      # single quoted string so hashes match the Zonefile's canonical format.
      strings = rdata.scan(/"([^"]*)"/).flatten
      %("#{strings.join}")
    end

    def normalize_trailing_period(value)
      value =~ /\.$/ ? value : value + "."
    end

    def http
      return @http if @http
      @http = HTTP.new("https://route53.amazonaws.com/2013-04-01/hostedzone/#{config.fetch(:hosted_zone_id)}/rrset")
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
      credential_scope = "#{date}/us-east-1/#{service}/aws4_request"
      string_to_sign = [
        algorithm,
        amz_date,
        credential_scope,
        OpenSSL::Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      signing_key = get_signature_key(config.fetch(:aws_secret_access_key), date, "us-east-1", service)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      "#{algorithm} Credential=#{config.fetch(:aws_access_key_id)}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
    end

    def get_signature_key(key, date_stamp, region_name, service_name)
      k_date = OpenSSL::HMAC.digest("SHA256", "AWS4" + key, date_stamp)
      k_region = OpenSSL::HMAC.digest("SHA256", k_date, region_name)
      k_service = OpenSSL::HMAC.digest("SHA256", k_region, service_name)
      OpenSSL::HMAC.digest("SHA256", k_service, "aws4_request")
    end
  end
end

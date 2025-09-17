# typed: strict
require "sorbet-runtime"

require "zonesync/record"
require "zonesync/http"
require "rexml/document"
require "erb"

module Zonesync
  class Route53 < Provider
    sig { returns(String) }
    def read
      @read = T.let(@read, T.nilable(String))
      @read ||= begin
        doc = REXML::Document.new(http.get(""))
        records = doc.elements.collect("*/ResourceRecordSets/ResourceRecordSet") do |record_set|
          to_records(record_set)
        end.flatten.sort
        records.map(&:to_s).join("\n") + "\n"
      end
    end

    sig { params(record: Record).void }
    def remove(record)
      if record.type == "TXT"
        # Route53 requires all TXT records with the same name to be managed together
        existing_txt_records = records.select do |r|
          r.name == record.name && r.type == "TXT"
        end

        if existing_txt_records.length == 1
          # Only one TXT record, delete it normally
          change_record("DELETE", record)
        else
          # Multiple TXT records - delete all, then recreate without the removed one
          remaining_txt_records = existing_txt_records.reject { |r| r == record }

          # Use change_records to handle both DELETE and CREATE in one request
          grouped = [
            [existing_txt_records, "DELETE"],
            [remaining_txt_records, "CREATE"]
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
                          <Value><%= group_record.rdata %></Value>
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
        end
      else
        change_record("DELETE", record)
      end
    end

    sig { params(old_record: Record, new_record: Record).void }
    def change(old_record, new_record)
      remove(old_record)
      add(new_record)
    end

    sig { params(record: Record).void }
    def add(record)
      add_with_duplicate_handling(record) do
        begin
          if record.type == "TXT"
            # Route53 requires all TXT records with the same name to be combined into a single record set
            existing_txt_records = records.select do |r|
              r.name == record.name && r.type == "TXT"
            end
            all_txt_records = existing_txt_records + [record]

            # Use UPSERT if records already exist, CREATE if they don't
            action = existing_txt_records.empty? ? "CREATE" : "UPSERT"
            change_records(action, all_txt_records)
          else
            change_record("CREATE", record)
          end
        rescue RuntimeError => e
          # Convert Route53-specific duplicate error to standard exception
          if e.message.include?("RRSet already exists")
            raise DuplicateRecordError.new(record, "Route53 duplicate record error")
          else
            # Re-raise other errors
            raise
          end
        end
      end
    end

    private

    sig { params(action: String, record: Record).void }
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
                      <Value>#{record.rdata}</Value>
                    </ResourceRecord>
                  </ResourceRecords>
                </ResourceRecordSet>
              </Change>
            </Changes>
          </ChangeBatch>
        </ChangeResourceRecordSetsRequest>
      XML
    end

    sig { params(action: String, records_list: T::Array[Record]).void }
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
                      <Value><%= record.rdata %></Value>
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

    sig { params(el: REXML::Element).returns(T::Array[Record]) }
    def to_records(el)
      el.elements.collect("ResourceRecords/ResourceRecord") do |rr|
        name = normalize_trailing_period(get_value(el, "Name"))
        type = get_value(el, "Type")
        ttl = get_value(el, "TTL")
        rdata = get_value(rr, "Value")

        record = Record.new(
          name:,
          type:,
          ttl:,
          rdata:,
          comment: nil, # Route 53 does not have a direct comment field
        )
      end
    end

    sig { params(el: REXML::Element, field: String).returns(String) }
    def get_value el, field
      el.elements[field].text.gsub(/\\(\d{3})/) { $1.to_i(8).chr } # unescape octal
    end

    sig { params(value: String).returns(String) }
    def normalize_trailing_period(value)
      value =~ /\.$/ ? value : value + "."
    end

    sig { returns(HTTP) }
    def http
      return @http if @http
      @http = T.let(HTTP.new("https://route53.amazonaws.com/2013-04-01/hostedzone/#{config.fetch(:hosted_zone_id)}/rrset"), T.nilable(Zonesync::HTTP))
      T.must(@http).before_request do |request, uri, body|
        request["Content-Type"] = "application/xml"
        request["X-Amz-Date"] = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        request["Authorization"] = sign_request(request.method, uri, body)
      end
      T.must(@http)
    end

    sig { params(method: String, uri: URI::HTTPS, body: T.nilable(String)).returns(String) }
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
      credential_scope = "#{date}/#{config.fetch(:aws_region)}/#{service}/aws4_request"
      string_to_sign = [
        algorithm,
        amz_date,
        credential_scope,
        OpenSSL::Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      signing_key = get_signature_key(config.fetch(:aws_secret_access_key), date, config.fetch(:aws_region), service)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      "#{algorithm} Credential=#{config.fetch(:aws_access_key_id)}/#{credential_scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
    end

    sig { params(key: String, date_stamp: String, region_name: String, service_name: String).returns(String) }
    def get_signature_key(key, date_stamp, region_name, service_name)
      k_date = OpenSSL::HMAC.digest("SHA256", "AWS4" + key, date_stamp)
      k_region = OpenSSL::HMAC.digest("SHA256", k_date, region_name)
      k_service = OpenSSL::HMAC.digest("SHA256", k_region, service_name)
      OpenSSL::HMAC.digest("SHA256", k_service, "aws4_request")
    end
  end
end


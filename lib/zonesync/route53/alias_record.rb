# frozen_string_literal: true

module Zonesync
  class Route53 < Provider
    class AliasRecord < Record
      TAG = /\broute53-alias(?:=(?<hosted_zone_id>\w+))?(?<evaluate_target_health>,evaluate-target-health)?(?!\S)/
      CLOUDFRONT_HOSTED_ZONE_ID = "Z2FDTNDATAQYW2"
      private_constant :TAG, :CLOUDFRONT_HOSTED_ZONE_ID

      def self.adopt(records)
        records = records.map { |record| from(record) }
        records.group_by { |record| [record.name, record.type] }.each_value { |rrset| of(rrset) }
        records
      end

      def self.of(rrset)
        alias_record = rrset.find { |record| record.is_a?(self) }
        if alias_record && rrset.length > 1
          raise UnsupportedRecordError.new(alias_record, "Route53 holds an alias as the only record of its name and type")
        end
        alias_record
      end

      def self.from(record)
        return record if record.is_a?(self)
        tag = record.comment&.match(TAG)
        named = %w[A AAAA].include?(record.type) && record.rdata.end_with?(".")
        return record unless tag || named
        raise UnsupportedRecordError.new(record, "route53-alias only applies to an A or AAAA record whose target is a fully qualified name") unless named
        raise UnsupportedRecordError.new(record, "Route53 holds an A or AAAA record that names a host only as an alias, tagged route53-alias") unless tag

        dns_name = record.rdata.downcase
        hosted_zone_id = tag[:hosted_zone_id] || (CLOUDFRONT_HOSTED_ZONE_ID if cloudfront?(dns_name))
        raise UnsupportedRecordError.new(record, "Only CloudFront's alias hosted zone is inferred; state this target's with route53-alias=<HostedZoneId>") unless hosted_zone_id

        build(
          name: record.name,
          type: record.type,
          dns_name: dns_name,
          hosted_zone_id: hosted_zone_id,
          evaluate_target_health: !!tag[:evaluate_target_health],
        )
      end

      def self.build(name:, type:, dns_name:, hosted_zone_id:, evaluate_target_health:)
        tag = +"route53-alias"
        tag << "=#{hosted_zone_id}" unless hosted_zone_id == CLOUDFRONT_HOSTED_ZONE_ID && cloudfront?(dns_name)
        tag << ",evaluate-target-health" if evaluate_target_health
        # Route53 holds no TTL for an alias, so the Zonefile's must not reach the manifest hash
        new(name: name, type: type, ttl: nil, rdata: dns_name, comment: tag)
      end

      def self.cloudfront?(dns_name)
        dns_name.end_with?(".cloudfront.net.")
      end

      def hosted_zone_id
        comment[TAG, :hosted_zone_id] || CLOUDFRONT_HOSTED_ZONE_ID
      end

      def evaluate_target_health
        !!comment[TAG, :evaluate_target_health]
      end

      def conflicts_with?(other)
        name == other.name && type == other.type
      end

      def to_h
        super.except(:ttl)
      end

      def to_s
        "#{name} #{type} #{rdata} ; #{comment}"
      end
    end
  end
end

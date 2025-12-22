# frozen_string_literal: true

module Zonesync
  class Cloudflare < Provider
    # Module that adds proxied support to individual Record instances.
    # When extended onto a record, it parses cf_tags=cf-proxied:true/false
    # from the comment and provides a proxied accessor.
    #
    # Semantics:
    # - cf_tags=cf-proxied:true  → explicitly enable Cloudflare proxy
    # - cf_tags=cf-proxied:false → explicitly disable Cloudflare proxy
    # - No cf_tags               → don't touch proxied (use Cloudflare default)
    module ProxiedSupport
      CF_TAGS_PATTERN = /\bcf_tags=cf-proxied:(true|false)\b/

      def self.extended(record)
        record.instance_variable_set :@original_comment, record[:comment]
      end

      def proxied
        @original_comment&.match(CF_TAGS_PATTERN) { |m| m[1] == "true" }
      end

      def comment
        return @original_comment unless @original_comment&.match?(CF_TAGS_PATTERN)
        cleaned = @original_comment.sub(/\s*#{CF_TAGS_PATTERN}\s*/, " ").strip
        cleaned.empty? ? nil : cleaned
      end

      def to_h
        super.merge(comment: comment, proxied: proxied)
      end

      def ==(other)
        other_proxied = other.respond_to?(:proxied) ? other.proxied : nil
        name == other.name &&
          type == other.type &&
          ttl == other.ttl &&
          rdata == other.rdata &&
          comment == other.comment &&
          proxied == other_proxied
      end
      alias eql? ==

      def hash
        [name, type, ttl, rdata, comment, proxied].hash
      end

      def to_s
        string = [name, ttl, type, rdata].join(" ")

        comment_parts = []
        comment_parts << "cf_tags=cf-proxied:true" if proxied == true
        comment_parts << comment if comment

        string << " ; #{comment_parts.join(' ')}" if comment_parts.any?
        string
      end
    end
  end
end

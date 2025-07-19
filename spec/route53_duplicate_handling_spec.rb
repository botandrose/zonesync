require "zonesync"

describe Zonesync::Route53 do
  context "graceful duplicate record handling" do
    it "handles 'RRSet already exists' error gracefully" do
      # Mock HTTP client that raises Route53's duplicate record error
      http_client = double("HTTP")
      
      # Mock the add request to return Route53's duplicate error
      error_response = "RRSet already exists"
      allow(http_client).to receive(:post).with("", anything).and_raise(RuntimeError.new(error_response))

      route53 = described_class.new({})
      allow(route53).to receive(:http).and_return(http_client)

      a_record = Zonesync::Record.new(
        name: "test.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      # Should not raise an error, should handle gracefully and print message
      expect { route53.add(a_record) }.to output(/Record already exists in .*Route53/).to_stdout
      expect { route53.add(a_record) }.not_to raise_error
    end

    it "still raises other Route53 API errors" do
      # Mock HTTP client that raises a different error
      http_client = double("HTTP")
      
      # Mock a different API error
      error_response = "InvalidChangeBatch: Some other error"
      allow(http_client).to receive(:post).with("", anything).and_raise(RuntimeError.new(error_response))

      route53 = described_class.new({})
      allow(route53).to receive(:http).and_return(http_client)

      a_record = Zonesync::Record.new(
        name: "test.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      # Should still raise other errors
      expect { route53.add(a_record) }.to raise_error(RuntimeError, /Some other error/)
    end

    it "converts Route53 duplicate errors to standard DuplicateRecordError" do
      # Mock HTTP client that raises Route53's duplicate record error
      http_client = double("HTTP")
      
      # Mock the add request to return Route53's duplicate error
      error_response = "RRSet already exists"
      allow(http_client).to receive(:post).with("", anything).and_raise(RuntimeError.new(error_response))

      route53 = described_class.new({})
      allow(route53).to receive(:http).and_return(http_client)

      # Override the add_with_duplicate_handling to capture the exception
      captured_exception = nil
      allow(route53).to receive(:add_with_duplicate_handling) do |record, &block|
        begin
          block.call
        rescue Zonesync::DuplicateRecordError => e
          captured_exception = e
        end
      end

      a_record = Zonesync::Record.new(
        name: "test.example.com.",
        type: "A",
        ttl: 3600,
        rdata: "192.0.2.1",
        comment: nil
      )

      route53.add(a_record)

      expect(captured_exception).to be_a(Zonesync::DuplicateRecordError)
      expect(captured_exception.record).to eq(a_record)
      expect(captured_exception.message).to include("Route53 duplicate record error")
    end

    it "works with MX records" do
      # Mock HTTP client that raises Route53's duplicate record error for MX
      http_client = double("HTTP")
      
      # Mock the add request to return Route53's duplicate error
      error_response = "RRSet already exists"
      allow(http_client).to receive(:post).with("", anything).and_raise(RuntimeError.new(error_response))

      route53 = described_class.new({})
      allow(route53).to receive(:http).and_return(http_client)

      mx_record = Zonesync::Record.new(
        name: "mail.example.com.",
        type: "MX",
        ttl: 3600,
        rdata: "10 mail.example.com.",
        comment: nil
      )

      # Should not raise an error, should handle gracefully
      expect { route53.add(mx_record) }.to output(/Record already exists in .*Route53/).to_stdout
      expect { route53.add(mx_record) }.not_to raise_error
    end
  end
end
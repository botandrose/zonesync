require "zonesync"

describe Zonesync::Provider do
  # Create a test provider that we can control
  class TestProvider < described_class
    def initialize(config = {})
      super(config)
      @should_raise_duplicate = false
    end

    def read
      "example.com. 1 SOA example.com. admin.example.com. 1 1 1 1 1\n"
    end

    def raise_duplicate_on_next_add!
      @should_raise_duplicate = true
    end

    def add(record)
      add_with_duplicate_handling(record) do
        if @should_raise_duplicate
          @should_raise_duplicate = false
          raise Zonesync::DuplicateRecordError.new(record, "Test duplicate error")
        end
        # Normal add logic would go here - for test we just succeed
      end
    end

    # Required abstract methods - minimal implementations for testing
    def remove(record); end
    def change(old_record, new_record); end
  end

  let(:provider) { TestProvider.new }
  let(:test_record) do
    Zonesync::Record.new(
      name: "test.example.com.",
      type: "A", 
      ttl: 3600,
      rdata: "192.0.2.1",
      comment: nil
    )
  end

  context "add_with_duplicate_handling method" do
    it "executes the block normally when no duplicate error occurs" do
      block_executed = false
      provider.send(:add_with_duplicate_handling, test_record) do
        block_executed = true
      end

      expect(block_executed).to be true
    end

    it "catches DuplicateRecordError and handles gracefully" do
      expect do
        provider.send(:add_with_duplicate_handling, test_record) do
          raise Zonesync::DuplicateRecordError.new(test_record, "Test error")
        end
      end.to output(/Record already exists in .*TestProvider: test\.example\.com\. A - will start tracking it/).to_stdout
    end

    it "re-raises other types of errors" do
      expect do
        provider.send(:add_with_duplicate_handling, test_record) do
          raise StandardError.new("Some other error")
        end
      end.to raise_error(StandardError, "Some other error")
    end

    it "includes provider class name in output message" do
      expect do
        provider.send(:add_with_duplicate_handling, test_record) do
          raise Zonesync::DuplicateRecordError.new(test_record, "Test error")
        end
      end.to output(/TestProvider/).to_stdout
    end

    it "includes record name and type in output message" do
      expect do
        provider.send(:add_with_duplicate_handling, test_record) do
          raise Zonesync::DuplicateRecordError.new(test_record, "Test error")
        end
      end.to output(/test\.example\.com\. A/).to_stdout
    end
  end

  context "integration with add method" do
    it "allows normal adds when no duplicate error occurs" do
      expect { provider.add(test_record) }.not_to raise_error
    end

    it "handles duplicate records gracefully in add method" do
      provider.raise_duplicate_on_next_add!
      
      expect { provider.add(test_record) }.to output(/Record already exists/).to_stdout
      expect { provider.add(test_record) }.not_to raise_error
    end
  end
end

describe Zonesync::DuplicateRecordError do
  let(:test_record) do
    Zonesync::Record.new(
      name: "test.example.com.",
      type: "A",
      ttl: 3600,
      rdata: "192.0.2.1",
      comment: nil
    )
  end

  context "initialization and methods" do
    it "stores the record and provider message" do
      error = described_class.new(test_record, "Provider specific message")
      
      expect(error.record).to eq(test_record)
      expect(error.message).to include("Record already exists: test.example.com. A")
      expect(error.message).to include("Provider specific message")
    end

    it "works without a provider message" do
      error = described_class.new(test_record)
      
      expect(error.record).to eq(test_record)
      expect(error.message).to eq("Record already exists: test.example.com. A")
    end

    it "includes record name and type in message" do
      error = described_class.new(test_record, "Test message")
      
      expect(error.message).to include("test.example.com.")
      expect(error.message).to include("A")
    end
  end
end
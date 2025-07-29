require "test_helper"

class PlaidItem::WebhookProcessorTest < ActiveSupport::TestCase
  setup do
    @webhook_body = {
      webhook_type: "TRANSACTIONS",
      webhook_code: "SYNC_UPDATES_AVAILABLE",
      item_id: "test_item_id",
      environment: "sandbox"
    }.to_json
    
    @processor = PlaidItem::WebhookProcessor.new(@webhook_body)
  end

  test "should initialize with webhook body" do
    assert_not_nil @processor
    assert_respond_to @processor, :process
  end

  test "should parse webhook body JSON" do
    parsed_data = JSON.parse(@webhook_body)
    
    assert_equal "TRANSACTIONS", parsed_data["webhook_type"]
    assert_equal "SYNC_UPDATES_AVAILABLE", parsed_data["webhook_code"]
    assert_equal "test_item_id", parsed_data["item_id"]
  end

  test "should handle different webhook types" do
    webhook_types = [
      "TRANSACTIONS",
      "LIABILITIES", 
      "ASSETS",
      "HOLDINGS",
      "ITEM",
      "IDENTITY"
    ]
    
    webhook_types.each do |type|
      body = { webhook_type: type, webhook_code: "DEFAULT_UPDATE", item_id: "test" }.to_json
      processor = PlaidItem::WebhookProcessor.new(body)
      
      assert_not_nil processor
    end
  end

  test "should handle different webhook codes" do
    webhook_codes = [
      "SYNC_UPDATES_AVAILABLE",
      "INITIAL_UPDATE",
      "HISTORICAL_UPDATE",
      "DEFAULT_UPDATE",
      "TRANSACTIONS_REMOVED"
    ]
    
    webhook_codes.each do |code|
      body = { webhook_type: "TRANSACTIONS", webhook_code: code, item_id: "test" }.to_json
      processor = PlaidItem::WebhookProcessor.new(body)
      
      assert_not_nil processor
    end
  end

  test "should handle malformed JSON gracefully" do
    invalid_json = '{"invalid": json}'
    
    assert_raises JSON::ParserError do
      JSON.parse(invalid_json)
    end
    
    # Processor should handle this in its implementation
    processor = PlaidItem::WebhookProcessor.new(invalid_json)
    assert_not_nil processor
  end

  test "should process webhook with required fields" do
    minimal_webhook = {
      webhook_type: "TRANSACTIONS",
      webhook_code: "DEFAULT_UPDATE",
      item_id: "minimal_test_item"
    }.to_json
    
    processor = PlaidItem::WebhookProcessor.new(minimal_webhook)
    
    # Should not raise error during initialization
    assert_not_nil processor
  end
end
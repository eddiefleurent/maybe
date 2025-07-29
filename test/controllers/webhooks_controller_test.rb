require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    
    # Valid Plaid webhook payload
    @valid_plaid_payload = {
      webhook_type: "TRANSACTIONS",
      webhook_code: "SYNC_UPDATES_AVAILABLE",
      item_id: "test_item_id",
      environment: "sandbox"
    }
    
    # Valid Stripe event payload
    @valid_stripe_payload = {
      id: "evt_test_webhook",
      object: "event",
      api_version: "2020-08-27",
      created: Time.current.to_i,
      data: {
        object: {
          id: "sub_test123",
          object: "subscription",
          status: "active"
        }
      },
      livemode: false,
      type: "customer.subscription.created"
    }
    
    # Valid Yodlee webhook payload
    @valid_yodlee_payload = {
      event: {
        name: "DATA_UPDATES",
        data: {
          providerAccountId: 123456
        }
      }
    }
  end

  # Plaid webhook tests
  test "should process valid Plaid webhook with correct verification header" do
    webhook_body = @valid_plaid_payload.to_json
    
    # Mock Plaid client and verification
    plaid_client = mock("plaid_client")
    plaid_client.expects(:validate_webhook!).with("test_verification_key", webhook_body).returns(true)
    Provider::Registry.expects(:plaid_provider_for_region).with(:us).returns(plaid_client)
    
    # Mock webhook processor
    webhook_processor = mock("webhook_processor")
    webhook_processor.expects(:process).returns(true)
    PlaidItem::WebhookProcessor.expects(:new).with(webhook_body).returns(webhook_processor)
    
    headers = {
      "Content-Type" => "application/json",
      "Plaid-Verification" => "test_verification_key"
    }
    
    post plaid_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should handle Plaid webhook verification failure" do
    webhook_body = @valid_plaid_payload.to_json
    
    # Mock Plaid client to raise verification error
    plaid_client = mock("plaid_client")
    plaid_client.expects(:validate_webhook!).raises(StandardError.new("Invalid verification"))
    Provider::Registry.expects(:plaid_provider_for_region).with(:us).returns(plaid_client)
    
    # Mock Sentry for error capture
    Sentry.expects(:capture_exception).with(instance_of(StandardError))
    
    headers = {
      "Content-Type" => "application/json",
      "Plaid-Verification" => "invalid_verification_key"
    }
    
    post plaid_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :bad_request
    
    response_body = JSON.parse(response.body)
    assert_equal "Invalid webhook: Invalid verification", response_body["error"]
  end

  test "should process valid Plaid EU webhook" do
    webhook_body = @valid_plaid_payload.to_json
    
    # Mock Plaid EU client
    plaid_client = mock("plaid_client")
    plaid_client.expects(:validate_webhook!).with("test_verification_key", webhook_body).returns(true)
    Provider::Registry.expects(:plaid_provider_for_region).with(:eu).returns(plaid_client)
    
    webhook_processor = mock("webhook_processor")
    webhook_processor.expects(:process).returns(true)
    PlaidItem::WebhookProcessor.expects(:new).with(webhook_body).returns(webhook_processor)
    
    headers = {
      "Content-Type" => "application/json",
      "Plaid-Verification" => "test_verification_key"
    }
    
    post plaid_eu_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should handle Plaid webhook processing exception" do
    webhook_body = @valid_plaid_payload.to_json
    
    plaid_client = mock("plaid_client")
    plaid_client.expects(:validate_webhook!).returns(true)
    Provider::Registry.expects(:plaid_provider_for_region).with(:us).returns(plaid_client)
    
    webhook_processor = mock("webhook_processor")
    webhook_processor.expects(:process).raises(StandardError.new("Processing failed"))
    PlaidItem::WebhookProcessor.expects(:new).returns(webhook_processor)
    
    Sentry.expects(:capture_exception).with(instance_of(StandardError))
    
    headers = {
      "Content-Type" => "application/json",
      "Plaid-Verification" => "test_verification_key"
    }
    
    post plaid_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :bad_request
    
    response_body = JSON.parse(response.body)
    assert_includes response_body["error"], "Processing failed"
  end

  # Stripe webhook tests
  test "should process valid Stripe webhook" do
    webhook_body = @valid_stripe_payload.to_json
    sig_header = "test_stripe_signature"
    
    # Mock Stripe provider
    stripe_provider = mock("stripe_provider")
    stripe_provider.expects(:process_webhook_later).with(webhook_body, sig_header).returns(true)
    Provider::Registry.expects(:get_provider).with(:stripe).returns(stripe_provider)
    
    headers = {
      "Content-Type" => "application/json",
      "Stripe-Signature" => sig_header
    }
    
    post stripe_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    assert_empty response.body
  end

  test "should handle Stripe JSON parser error" do
    invalid_json = '{"invalid": json}'
    
    stripe_provider = mock("stripe_provider")
    stripe_provider.expects(:process_webhook_later).raises(JSON::ParserError.new("Invalid JSON"))
    Provider::Registry.expects(:get_provider).with(:stripe).returns(stripe_provider)
    
    Sentry.expects(:capture_exception).with(instance_of(JSON::ParserError))
    Rails.logger.expects(:error).with("JSON parser error: Invalid JSON")
    
    headers = {
      "Content-Type" => "application/json",
      "Stripe-Signature" => "test_signature"
    }
    
    post stripe_webhooks_path, params: invalid_json, headers: headers
    
    assert_response :bad_request
    assert_empty response.body
  end

  test "should handle Stripe signature verification error" do
    webhook_body = @valid_stripe_payload.to_json
    
    stripe_provider = mock("stripe_provider")
    stripe_provider.expects(:process_webhook_later).raises(Stripe::SignatureVerificationError.new("Invalid signature", "test_sig"))
    Provider::Registry.expects(:get_provider).with(:stripe).returns(stripe_provider)
    
    Sentry.expects(:capture_exception).with(instance_of(Stripe::SignatureVerificationError))
    Rails.logger.expects(:error).with("Stripe signature verification error: Invalid signature")
    
    headers = {
      "Content-Type" => "application/json",
      "Stripe-Signature" => "invalid_signature"
    }
    
    post stripe_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :bad_request
    assert_empty response.body
  end

  test "should handle Stripe webhook without signature header" do
    webhook_body = @valid_stripe_payload.to_json
    
    stripe_provider = mock("stripe_provider")
    stripe_provider.expects(:process_webhook_later).with(webhook_body, nil).returns(true)
    Provider::Registry.expects(:get_provider).with(:stripe).returns(stripe_provider)
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post stripe_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
  end

  # Yodlee webhook tests
  test "should process valid Yodlee webhook with provider account ID" do
    webhook_body = @valid_yodlee_payload.to_json
    
    # Create mock YodleeItem
    yodlee_item = mock("yodlee_item")
    yodlee_item.expects(:syncing?).returns(false)
    yodlee_item.expects(:sync_later).returns(true)
    
    # Mock YodleeItem query chain
    active_scope = mock("active_scope")
    where_scope = mock("where_scope")
    
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:where).with(yodlee_id: ["123456"]).returns(where_scope)
    where_scope.expects(:find_each).yields(yodlee_item)
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should handle Yodlee webhook with multiple provider account IDs" do
    multi_account_payload = {
      event: {
        name: "DATA_UPDATES",
        data: {
          providerAccountId: [123456, 789012]
        }
      }
    }
    webhook_body = multi_account_payload.to_json
    
    yodlee_item1 = mock("yodlee_item1")
    yodlee_item1.expects(:syncing?).returns(false)
    yodlee_item1.expects(:sync_later).returns(true)
    
    yodlee_item2 = mock("yodlee_item2")
    yodlee_item2.expects(:syncing?).returns(true) # Already syncing
    
    active_scope = mock("active_scope")
    where_scope = mock("where_scope")
    
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:where).with(yodlee_id: ["123456", "789012"]).returns(where_scope)
    where_scope.expects(:find_each).multiple_yields([yodlee_item1], [yodlee_item2])
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should handle Yodlee webhook without provider account ID" do
    payload_without_id = {
      event: {
        name: "DATA_UPDATES",
        data: {}
      }
    }
    webhook_body = payload_without_id.to_json
    
    # Mock fallback behavior - sync all active items
    yodlee_item = mock("yodlee_item")
    yodlee_item.expects(:syncing?).returns(false)
    yodlee_item.expects(:sync_later).returns(true)
    
    active_scope = mock("active_scope")
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:find_each).yields(yodlee_item)
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should handle Yodlee webhook with malformed JSON" do
    invalid_json = '{"invalid": json}'
    
    Rails.logger.expects(:error).with("Yodlee webhook JSON parse error: unexpected token at '{\"invalid\": json}'")
    Sentry.expects(:capture_exception).with(instance_of(JSON::ParserError))
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: invalid_json, headers: headers
    
    assert_response :bad_request
    
    response_body = JSON.parse(response.body)
    assert_equal "Invalid JSON", response_body["error"]
  end

  test "should handle Yodlee webhook processing exception" do
    webhook_body = @valid_yodlee_payload.to_json
    
    YodleeItem.expects(:active).raises(StandardError.new("Database error"))
    Sentry.expects(:capture_exception).with(instance_of(StandardError))
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :bad_request
    
    response_body = JSON.parse(response.body)
    assert_includes response_body["error"], "Database error"
  end

  test "should handle empty Yodlee webhook payload" do
    empty_payload = "{}"
    
    # Should trigger fallback behavior
    yodlee_item = mock("yodlee_item")
    yodlee_item.expects(:syncing?).returns(false)
    yodlee_item.expects(:sync_later).returns(true)
    
    active_scope = mock("active_scope")
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:find_each).yields(yodlee_item)
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: empty_payload, headers: headers
    
    assert_response :ok
    
    response_body = JSON.parse(response.body)
    assert_equal true, response_body["received"]
  end

  test "should skip already syncing YodleeItems" do
    webhook_body = @valid_yodlee_payload.to_json
    
    syncing_item = mock("syncing_item")
    syncing_item.expects(:syncing?).returns(true)
    syncing_item.expects(:sync_later).never
    
    not_syncing_item = mock("not_syncing_item")
    not_syncing_item.expects(:syncing?).returns(false)
    not_syncing_item.expects(:sync_later).returns(true)
    
    active_scope = mock("active_scope")
    where_scope = mock("where_scope")
    
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:where).returns(where_scope)
    where_scope.expects(:find_each).multiple_yields([syncing_item], [not_syncing_item])
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
  end

  test "should handle Yodlee webhook with array of provider account IDs" do
    array_payload = {
      event: {
        name: "DATA_UPDATES",
        data: {
          providerAccountId: [123456, 789012, 345678]
        }
      }
    }
    webhook_body = array_payload.to_json
    
    active_scope = mock("active_scope")
    where_scope = mock("where_scope")
    
    YodleeItem.expects(:active).returns(active_scope)
    active_scope.expects(:where).with(yodlee_id: ["123456", "789012", "345678"]).returns(where_scope)
    where_scope.expects(:find_each).returns([])
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    post yodlee_webhooks_path, params: webhook_body, headers: headers
    
    assert_response :ok
  end

  # Authentication and CSRF tests
  test "should skip authentication for all webhook endpoints" do
    # These tests verify that the skip_authentication and skip_before_action work
    # by ensuring we can call the endpoints without authentication
    
    # Mock necessary objects for each endpoint
    Provider::Registry.stubs(:plaid_provider_for_region).returns(mock("client", validate_webhook!: true))
    PlaidItem::WebhookProcessor.stubs(:new).returns(mock("processor", process: true))
    
    Provider::Registry.stubs(:get_provider).returns(mock("stripe", process_webhook_later: true))
    
    YodleeItem.stubs(:active).returns(mock("scope", find_each: []))
    
    # Test all endpoints without authentication
    post plaid_webhooks_path, params: @valid_plaid_payload.to_json, headers: { "Plaid-Verification" => "test" }
    assert_response :ok
    
    post plaid_eu_webhooks_path, params: @valid_plaid_payload.to_json, headers: { "Plaid-Verification" => "test" }
    assert_response :ok
    
    post stripe_webhooks_path, params: @valid_stripe_payload.to_json, headers: { "Stripe-Signature" => "test" }
    assert_response :ok
    
    post yodlee_webhooks_path, params: @valid_yodlee_payload.to_json
    assert_response :ok
  end

  test "should skip CSRF token verification for all webhook endpoints" do
    # Rails normally requires CSRF tokens, but webhooks should skip this
    # This is handled by skip_before_action :verify_authenticity_token
    
    # Mock necessary dependencies
    Provider::Registry.stubs(:plaid_provider_for_region).returns(mock("client", validate_webhook!: true))
    PlaidItem::WebhookProcessor.stubs(:new).returns(mock("processor", process: true))
    
    # Make request without CSRF token - should succeed
    post plaid_webhooks_path, params: @valid_plaid_payload.to_json, headers: { "Plaid-Verification" => "test" }
    assert_response :ok
  end
end

require "test_helper"

class Family::YodleeConnectableTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:dylan)
    @mock_provider = mock
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(@mock_provider)
  end

  teardown do
    # Clean up any stubbed methods
    Provider::Registry.unstub(:get_provider)
    Rails.application.config.unstub(:enable_yodlee) if Rails.application.config.respond_to?(:unstub)
  end

  # Test association
  test "has many yodlee_items with dependent destroy" do
    # Test the association exists
    assert_respond_to @family, :yodlee_items
    
    # Create a yodlee item to test dependent destroy
    yodlee_item = @family.yodlee_items.create!(
      name: "Test Bank",
      user_session: "test_session_123",
      raw_payload: { provider: "test_bank" }
    )
    
    assert_equal 1, @family.yodlee_items.count
    
    # Test dependent destroy
    @family.destroy
    assert_equal 0, YodleeItem.where(id: yodlee_item.id).count
  end

  # Test can_connect_yodlee? method
  test "can_connect_yodlee? returns true when provider present and yodlee enabled" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    result = @family.can_connect_yodlee?
    assert result
  end

  test "can_connect_yodlee? returns false when provider is nil" do
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(nil)
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    result = @family.can_connect_yodlee?
    assert_not result
  end

  test "can_connect_yodlee? returns false when yodlee is disabled" do
    Rails.application.config.stubs(:enable_yodlee).returns(false)
    
    result = @family.can_connect_yodlee?
    assert_not result
  end

  test "can_connect_yodlee? returns false when both provider nil and yodlee disabled" do
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(nil)
    Rails.application.config.stubs(:enable_yodlee).returns(false)
    
    result = @family.can_connect_yodlee?
    assert_not result
  end

  # Test create_yodlee_item! method
  test "create_yodlee_item! creates new yodlee item with required parameters" do
    user_session = "test_session_456"
    item_name = "Chase Bank"
    metadata = { account_type: "checking", balance: 1500.0 }

    assert_difference "@family.yodlee_items.count", 1 do
      yodlee_item = @family.create_yodlee_item!(
        user_session: user_session,
        item_name: item_name,
        metadata: metadata
      )
      
      assert_equal item_name, yodlee_item.name
      assert_equal user_session, yodlee_item.user_session
      assert_equal metadata, yodlee_item.raw_payload
      assert_equal @family, yodlee_item.family
    end
  end

  test "create_yodlee_item! calls sync_later on created item" do
    user_session = "test_session_789"
    item_name = "Bank of America"
    
    # Mock the sync_later method
    YodleeItem.any_instance.expects(:sync_later).once
    
    @family.create_yodlee_item!(
      user_session: user_session,
      item_name: item_name,
      metadata: { test: "data" }
    )
  end

  test "create_yodlee_item! handles empty metadata gracefully" do
    user_session = "test_session_empty"
    item_name = "Wells Fargo"
    
    yodlee_item = @family.create_yodlee_item!(
      user_session: user_session,
      item_name: item_name,
      metadata: {}
    )
    
    assert_equal({}, yodlee_item.raw_payload)
  end

  test "create_yodlee_item! raises error with missing required parameters" do
    assert_raises ArgumentError do
      @family.create_yodlee_item!(item_name: "Test Bank")
    end
    
    assert_raises ArgumentError do
      @family.create_yodlee_item!(user_session: "session123")
    end
  end

  # Test get_yodlee_token method
  test "get_yodlee_token returns token when can_connect_yodlee is true" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    # Mock the user creation and token generation
    user_session = "mock_user_session"
    @family.stubs(:find_or_create_yodlee_user).returns(user_session)
    
    expected_token_response = {
      cobrand_token: "cobrand_123",
      user_token: "user_456",
      fastlink_url: "https://fastlink.yodlee.com"
    }
    @mock_provider.expects(:get_fastlink_token).with(user_session).returns(expected_token_response)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_equal expected_token_response, result
  end

  test "get_yodlee_token returns nil when cannot connect to yodlee" do
    Rails.application.config.stubs(:enable_yodlee).returns(false)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  test "get_yodlee_token returns nil when user session creation fails" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    @family.stubs(:find_or_create_yodlee_user).returns(nil)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  test "get_yodlee_token handles provider errors gracefully" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    user_session = "mock_user_session"
    @family.stubs(:find_or_create_yodlee_user).returns(user_session)
    
    # Mock provider to raise an error
    @mock_provider.expects(:get_fastlink_token).raises(StandardError.new("API Error"))
    
    # Mock logger and Sentry
    Rails.logger.expects(:error).with("Failed to get Yodlee token: API Error")
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  test "get_yodlee_token logs errors with Sentry when available" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    user_session = "mock_user_session"
    @family.stubs(:find_or_create_yodlee_user).returns(user_session)
    
    error = StandardError.new("API Error")
    @mock_provider.expects(:get_fastlink_token).raises(error)
    
    # Mock Sentry if it's defined
    if defined?(Sentry)
      Sentry.expects(:capture_exception).with(error)
    end
    
    Rails.logger.stubs(:error)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  # Test private find_or_create_yodlee_user method (indirectly)
  test "find_or_create_yodlee_user returns existing user session from active item" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    # Create an active yodlee item
    existing_session = "existing_session_123"
    yodlee_item = @family.yodlee_items.create!(
      name: "Existing Bank",
      user_session: existing_session,
      raw_payload: { status: "active" }
    )
    
    # Mock active scope to return the item
    @family.yodlee_items.stubs(:active).returns([yodlee_item])
    
    @mock_provider.expects(:get_fastlink_token).with(existing_session).returns({})
    
    @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
  end

  test "find_or_create_yodlee_user creates new user when no active items exist" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    # Mock no existing active items
    @family.yodlee_items.stubs(:active).returns([])
    
    # Mock user finding
    @family.users.stubs(:find_by).with(role: :admin).returns(@user)
    
    new_session = "new_session_789"
    @mock_provider.expects(:create_user).with(@user).returns(new_session)
    @mock_provider.expects(:get_fastlink_token).with(new_session).returns({})
    
    @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
  end

  test "find_or_create_yodlee_user falls back to first user when no admin exists" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    @family.yodlee_items.stubs(:active).returns([])
    @family.users.stubs(:find_by).with(role: :admin).returns(nil)
    @family.users.stubs(:first).returns(@user)
    
    new_session = "fallback_session_456"
    @mock_provider.expects(:create_user).with(@user).returns(new_session)
    @mock_provider.expects(:get_fastlink_token).with(new_session).returns({})
    
    @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
  end

  test "find_or_create_yodlee_user returns nil when no users exist" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    @family.yodlee_items.stubs(:active).returns([])
    @family.users.stubs(:find_by).with(role: :admin).returns(nil)
    @family.users.stubs(:first).returns(nil)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  # Test edge cases and error scenarios
  test "yodlee methods handle network timeouts" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    user_session = "timeout_session"
    @family.stubs(:find_or_create_yodlee_user).returns(user_session)
    
    @mock_provider.expects(:get_fastlink_token).raises(Net::TimeoutError.new("Request timeout"))
    Rails.logger.stubs(:error)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_nil result
  end

  test "create_yodlee_item! handles validation errors gracefully" do
    # Mock invalid attributes that would cause validation to fail
    YodleeItem.any_instance.stubs(:valid?).returns(false)
    YodleeItem.any_instance.stubs(:errors).returns(
      double("errors", full_messages: ["Name can't be blank"])
    )
    
    assert_raises ActiveRecord::RecordInvalid do
      @family.create_yodlee_item!(
        user_session: "",
        item_name: "",
        metadata: {}
      )
    end
  end

  # Test integration scenarios
  test "full yodlee connection workflow" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    # Step 1: Check if can connect
    assert @family.can_connect_yodlee?
    
    # Step 2: Get token successfully
    user_session = "integration_session"
    @family.yodlee_items.stubs(:active).returns([])
    @family.users.stubs(:find_by).with(role: :admin).returns(@user)
    @mock_provider.expects(:create_user).with(@user).returns(user_session)
    
    token_response = { cobrand_token: "token123", user_token: "user456" }
    @mock_provider.expects(:get_fastlink_token).with(user_session).returns(token_response)
    
    result = @family.get_yodlee_token(
      webhooks_url: "https://example.com/webhooks",
      redirect_url: "https://example.com/redirect"
    )
    
    assert_equal token_response, result
    
    # Step 3: Create yodlee item after successful connection
    YodleeItem.any_instance.expects(:sync_later).once
    
    yodlee_item = @family.create_yodlee_item!(
      user_session: user_session,
      item_name: "Connected Bank",
      metadata: { connection_id: "conn_123" }
    )
    
    assert_not_nil yodlee_item
    assert_equal "Connected Bank", yodlee_item.name
    assert_equal user_session, yodlee_item.user_session
  end

  # Test parameter validation
  test "get_yodlee_token requires webhooks_url parameter" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    assert_raises ArgumentError do
      @family.get_yodlee_token(redirect_url: "https://example.com/redirect")
    end
  end

  test "get_yodlee_token requires redirect_url parameter" do
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    assert_raises ArgumentError do
      @family.get_yodlee_token(webhooks_url: "https://example.com/webhooks")
    end
  end

  # Test provider registry behavior
  test "yodlee_provider method returns correct provider" do
    # This tests the private method indirectly
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    # The provider should be called through the registry
    Provider::Registry.expects(:get_provider).with(:yodlee).returns(@mock_provider).at_least_once
    
    @family.can_connect_yodlee?
  end

  test "handles provider registry returning nil gracefully" do
    Provider::Registry.stubs(:get_provider).with(:yodlee).returns(nil)
    Rails.application.config.stubs(:enable_yodlee).returns(true)
    
    assert_not @family.can_connect_yodlee?
  end
end
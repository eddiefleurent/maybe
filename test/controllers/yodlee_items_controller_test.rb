require 'test_helper'

class YodleeItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:one)
    @user = users(:one)
    @user.update!(family: @family)
    Current.family = @family
    sign_in @user
    @yodlee_item = yodlee_items(:one)
    @yodlee_item.update!(family: @family)
  end

  # Test new action - Happy path
  test "should get new with valid token response" do
    token_response = { "access_token" => "test_token", "expires_in" => 3600 }
    @family.expects(:get_yodlee_token).returns(token_response)

    get new_yodlee_item_url

    assert_response :success
    assert_equal token_response, assigns(:token_response)
  end

  # Test new action - Error case when token is nil
  test "should redirect to accounts with alert when token response is nil" do
    @family.expects(:get_yodlee_token).returns(nil)

    get new_yodlee_item_url

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.new.error"), flash[:alert]
  end

  # Test new action - Error case when token is false
  test "should redirect to accounts with alert when token response is false" do
    @family.expects(:get_yodlee_token).returns(false)

    get new_yodlee_item_url

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.new.error"), flash[:alert]
  end

  # Test new action - Verify correct parameters passed to get_yodlee_token
  test "should pass correct parameters to get_yodlee_token in new action" do
    expected_webhooks_url = webhooks_yodlee_url
    expected_redirect_url = accounts_url

    @family.expects(:get_yodlee_token)
           .with(webhooks_url: expected_webhooks_url, redirect_url: expected_redirect_url)
           .returns({ "access_token" => "test_token" })

    get new_yodlee_item_url

    assert_response :success
  end

  # Test edit action - Happy path
  test "should get edit with valid token response" do
    token_response = { "update_token" => "update_test_token", "expires_in" => 1800 }
    @yodlee_item.expects(:get_update_link_token).returns(token_response)

    get edit_yodlee_item_url(@yodlee_item)

    assert_response :success
    assert_equal token_response, assigns(:token_response)
    assert_equal @yodlee_item, assigns(:yodlee_item)
  end

  # Test edit action - Error case when token is nil
  test "should redirect to accounts with alert when update token response is nil" do
    @yodlee_item.expects(:get_update_link_token).returns(nil)

    get edit_yodlee_item_url(@yodlee_item)

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.edit.error"), flash[:alert]
  end

  # Test edit action - Error case when token is false
  test "should redirect to accounts with alert when update token response is false" do
    @yodlee_item.expects(:get_update_link_token).returns(false)

    get edit_yodlee_item_url(@yodlee_item)

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.edit.error"), flash[:alert]
  end

  # Test edit action - Verify correct parameters passed to get_update_link_token
  test "should pass correct parameters to get_update_link_token in edit action" do
    expected_webhooks_url = webhooks_yodlee_url
    expected_redirect_url = accounts_url

    @yodlee_item.expects(:get_update_link_token)
                .with(webhooks_url: expected_webhooks_url, redirect_url: expected_redirect_url)
                .returns({ "update_token" => "test_token" })

    get edit_yodlee_item_url(@yodlee_item)

    assert_response :success
  end

  # Test create action - Happy path
  test "should create yodlee item successfully" do
    user_session = "test_session_123"
    item_name = "Test Bank"
    metadata = { "institution" => { "name" => item_name } }

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: item_name, metadata: metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  # Test create action - Error handling with StandardError
  test "should handle StandardError in create action" do
    user_session = "test_session_456"
    metadata = { "providerName" => "Error Bank" }
    error_message = "Connection failed"

    @family.expects(:create_yodlee_item!).raises(StandardError.new(error_message))
    Rails.logger.expects(:error).with("Failed to create Yodlee item: #{error_message}")

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.error"), flash[:alert]
  end

  # Test create action - Error handling with Sentry integration
  test "should capture exception with Sentry when defined" do
    user_session = "test_session_789"
    metadata = { "institution" => { "name" => "Sentry Bank" } }
    error = StandardError.new("Sentry test error")

    @family.expects(:create_yodlee_item!).raises(error)
    Rails.logger.expects(:error)

    # Mock Sentry if it's defined
    stub_const("Sentry", Class.new) do
      Sentry.expects(:capture_exception).with(error)

      post yodlee_items_url, params: {
        yodlee_item: {
          user_session: user_session,
          metadata: metadata
        }
      }
    end

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.error"), flash[:alert]
  end

  # Test create action - Item name extraction from institution name
  test "should extract item name from metadata institution name" do
    user_session = "test_session_institution"
    institution_name = "First National Bank"
    metadata = { "institution" => { "name" => institution_name } }

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: institution_name, metadata: metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  # Test create action - Item name extraction from providerName
  test "should extract item name from metadata providerName" do
    user_session = "test_session_provider"
    provider_name = "Credit Union Provider"
    metadata = { "providerName" => provider_name }

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: provider_name, metadata: metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  # Test create action - Default item name when no institution or provider name
  test "should use default item name when metadata lacks institution and provider name" do
    user_session = "test_session_default"
    metadata = { "some_other_field" => "value" }
    default_name = "Financial Institution"

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: default_name, metadata: metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  # Test destroy action - Happy path
  test "should destroy yodlee item successfully" do
    @yodlee_item.expects(:destroy_later).returns(true)

    delete yodlee_item_url(@yodlee_item)

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.destroy.success"), flash[:notice]
  end

  # Test sync action - When item is not syncing (HTML format)
  test "should sync yodlee item when not currently syncing with HTML format" do
    @yodlee_item.expects(:syncing?).returns(false)
    @yodlee_item.expects(:sync_later).returns(true)

    patch sync_yodlee_item_url(@yodlee_item)

    assert_redirected_to accounts_path
  end

  # Test sync action - When item is not syncing (JSON format)
  test "should sync yodlee item when not currently syncing with JSON format" do
    @yodlee_item.expects(:syncing?).returns(false)
    @yodlee_item.expects(:sync_later).returns(true)

    patch sync_yodlee_item_url(@yodlee_item), params: { format: :json }

    assert_response :ok
  end

  # Test sync action - When item is already syncing (HTML format)
  test "should not sync yodlee item when already syncing with HTML format" do
    @yodlee_item.expects(:syncing?).returns(true)
    @yodlee_item.expects(:sync_later).never

    patch sync_yodlee_item_url(@yodlee_item)

    assert_redirected_to accounts_path
  end

  # Test sync action - When item is already syncing (JSON format)
  test "should not sync yodlee item when already syncing with JSON format" do
    @yodlee_item.expects(:syncing?).returns(true)
    @yodlee_item.expects(:sync_later).never

    patch sync_yodlee_item_url(@yodlee_item), params: { format: :json }

    assert_response :ok
  end

  # Test sync action - Redirect back functionality
  test "should redirect back to referrer in sync action" do
    referrer_url = "#{root_url}some_page"
    @yodlee_item.expects(:syncing?).returns(false)
    @yodlee_item.expects(:sync_later).returns(true)

    patch sync_yodlee_item_url(@yodlee_item), headers: { "HTTP_REFERER" => referrer_url }

    assert_redirected_to referrer_url
  end

  # Test parameter validation
  test "should require yodlee_item parameters for create" do
    assert_raises(ActionController::ParameterMissing) do
      post yodlee_items_url, params: {}
    end
  end

  # Test parameter validation - Missing user_session
  test "should handle missing user_session parameter" do
    @family.expects(:create_yodlee_item!)
           .with(user_session: nil, item_name: "Financial Institution", metadata: {})
           .returns(true)

    post yodlee_items_url, params: { yodlee_item: { metadata: {} } }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  # Test authorization - Item must belong to current family
  test "should only find yodlee items belonging to current family" do
    other_family = families(:two)
    other_item = yodlee_items(:two)
    other_item.update!(family: other_family)

    assert_raises(ActiveRecord::RecordNotFound) do
      get edit_yodlee_item_url(other_item)
    end
  end

  # Test authorization - set_yodlee_item filter
  test "should set yodlee item from current family scope in edit" do
    get edit_yodlee_item_url(@yodlee_item)

    assert_equal @yodlee_item, assigns(:yodlee_item)
  end

  test "should set yodlee item from current family scope in destroy" do
    @yodlee_item.expects(:destroy_later).returns(true)

    delete yodlee_item_url(@yodlee_item)

    assert_equal @yodlee_item, assigns(:yodlee_item)
  end

  test "should set yodlee item from current family scope in sync" do
    @yodlee_item.expects(:syncing?).returns(false)
    @yodlee_item.expects(:sync_later).returns(true)

    patch sync_yodlee_item_url(@yodlee_item)

    assert_equal @yodlee_item, assigns(:yodlee_item)
  end

  # Test webhooks URL generation
  test "should generate correct webhooks URL in production" do
    Rails.env.expects(:production?).returns(true)

    token_response = { "access_token" => "test_token" }
    expected_webhooks_url = webhooks_yodlee_url

    @family.expects(:get_yodlee_token)
           .with(webhooks_url: expected_webhooks_url, redirect_url: accounts_url)
           .returns(token_response)

    get new_yodlee_item_url

    assert_response :success
  end

  test "should generate correct webhooks URL in development with ENV variable" do
    Rails.env.expects(:production?).returns(false)
    ENV.expects(:fetch).with("DEV_WEBHOOKS_URL", root_url.chomp("/")).returns("https://dev.example.com")

    token_response = { "access_token" => "test_token" }
    expected_webhooks_url = "https://dev.example.com/webhooks/yodlee"

    @family.expects(:get_yodlee_token)
           .with(webhooks_url: expected_webhooks_url, redirect_url: accounts_url)
           .returns(token_response)

    get new_yodlee_item_url

    assert_response :success
  end

  test "should generate correct webhooks URL in development without ENV variable" do
    Rails.env.expects(:production?).returns(false)
    root_url_without_slash = root_url.chomp("/")
    ENV.expects(:fetch).with("DEV_WEBHOOKS_URL", root_url_without_slash).returns(root_url_without_slash)

    token_response = { "access_token" => "test_token" }
    expected_webhooks_url = "#{root_url_without_slash}/webhooks/yodlee"

    @family.expects(:get_yodlee_token)
           .with(webhooks_url: expected_webhooks_url, redirect_url: accounts_url)
           .returns(token_response)

    get new_yodlee_item_url

    assert_response :success
  end

  # Test edge cases and error conditions
  test "should handle empty metadata gracefully" do
    user_session = "test_session_empty"
    metadata = {}

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: "Financial Institution", metadata: metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  test "should handle nil metadata gracefully" do
    user_session = "test_session_nil"

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: "Financial Institution", metadata: {})
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  test "should handle complex nested metadata" do
    user_session = "test_session_complex"
    complex_metadata = {
      "institution" => { "name" => "Complex Bank" },
      "providerName" => "Should not be used",
      "accounts" => [
        { "id" => "acc1", "type" => "checking" },
        { "id" => "acc2", "type" => "savings" }
      ],
      "extra_data" => { "field1" => "value1", "field2" => "value2" }
    }

    @family.expects(:create_yodlee_item!)
           .with(user_session: user_session, item_name: "Complex Bank", metadata: complex_metadata)
           .returns(true)

    post yodlee_items_url, params: {
      yodlee_item: {
        user_session: user_session,
        metadata: complex_metadata
      }
    }

    assert_redirected_to accounts_path
    assert_equal I18n.t("yodlee_items.create.success"), flash[:notice]
  end

  private

  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out(user)
    session[:user_id] = nil
  end

  def stub_const(const_name, value)
    original_value = Object.const_get(const_name) if Object.const_defined?(const_name)
    Object.const_set(const_name, value)
    yield
  ensure
    if original_value
      Object.const_set(const_name, original_value)
    else
      Object.send(:remove_const, const_name)
    end
  end
end

<!-- SKIPPED FIX: The reported hardcoded passphrase issue is a false positive; no passphrase present in this test file. -->
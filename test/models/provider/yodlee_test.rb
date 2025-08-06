require "test_helper"

class Provider::YodleeTest < ActiveSupport::TestCase
  def setup
    @config = {
      client_id: "test_client_id",
      secret: "test_secret", 
      base_url: "https://sandbox.api.yodlee.com/ysl",
      fastlink_url: "https://fl4.sandbox.yodlee.com/authenticate/restserver/fastlink"
    }
    @provider = Provider::Yodlee.new(@config)
  end

  test "initializes with correct configuration" do
    assert_equal "test_client_id", @provider.client_id
    assert_equal "test_secret", @provider.secret
    assert_equal "https://sandbox.api.yodlee.com/ysl", @provider.base_url
    assert_equal "https://fl4.sandbox.yodlee.com/authenticate/restserver/fastlink", @provider.fastlink_url
  end

  test "has correct API version" do
    assert_equal "1.1", Provider::Yodlee::API_VERSION
  end

  test "responds to all required v1.1 methods" do
    required_methods = [
      :generate_access_token, :client_token, :create_user,
      :get_accounts, :get_transactions, :get_institutions, 
      :get_user, :fastlink_bundle
    ]
    
    required_methods.each do |method|
      assert_respond_to @provider, method, "Provider should respond to #{method}"
    end
  end

  test "fastlink_bundle returns correct structure" do
    token = "fake_token_123"
    bundle = @provider.fastlink_bundle(token)
    
    assert_instance_of Provider::Yodlee::FastLinkTokenResponse, bundle
    assert_equal token, bundle.user_token
    assert_equal @provider.fastlink_url, bundle.fastlink_url
  end

  # Integration tests (require real credentials)
  if ENV["ENABLE_YODLEE"] == "true" && ENV["YODLEE_CLIENT_ID"].present?
    test "can generate client token with real credentials" do
      skip "Skipping live API test" unless ENV["YODLEE_INTEGRATION_TEST"] == "true"
      
      provider = Provider::Registry.get_provider(:yodlee)
      token = provider.client_token
      
      assert_not_nil token, "Should generate a client token"
      assert token.length > 20, "Token should be reasonable length"
    end

    test "can retrieve institutions with real credentials" do
      skip "Skipping live API test" unless ENV["YODLEE_INTEGRATION_TEST"] == "true"
      
      provider = Provider::Registry.get_provider(:yodlee)
      institutions = provider.get_institutions
      
      assert_instance_of Array, institutions
      assert institutions.length > 0, "Should find institutions"
    end
  end
end 
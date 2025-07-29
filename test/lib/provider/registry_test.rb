require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "should return Plaid provider for US region" do
    provider = Provider::Registry.plaid_provider_for_region(:us)
    
    assert_not_nil provider
    assert_respond_to provider, :validate_webhook!
  end

  test "should return Plaid provider for EU region" do  
    provider = Provider::Registry.plaid_provider_for_region(:eu)
    
    assert_not_nil provider
    assert_respond_to provider, :validate_webhook!
  end

  test "should return different providers for different regions" do
    us_provider = Provider::Registry.plaid_provider_for_region(:us)
    eu_provider = Provider::Registry.plaid_provider_for_region(:eu)
    
    # They should be different instances configured for different regions
    assert_not_equal us_provider.object_id, eu_provider.object_id
  end

  test "should return Stripe provider" do
    provider = Provider::Registry.get_provider(:stripe)
    
    assert_not_nil provider
    assert_respond_to provider, :process_webhook_later
  end

  test "should handle unknown provider gracefully" do
    assert_raises StandardError do
      Provider::Registry.get_provider(:unknown_provider)
    end
  end

  test "should handle invalid region for Plaid" do
    assert_raises ArgumentError do
      Provider::Registry.plaid_provider_for_region(:invalid_region)
    end
  end

  test "should cache provider instances" do
    provider1 = Provider::Registry.get_provider(:stripe)
    provider2 = Provider::Registry.get_provider(:stripe)
    
    # Should return the same instance (cached)
    assert_equal provider1.object_id, provider2.object_id
  end
end